// p9_bodyclose —— resp.Body「读不读完 / 关不关」到底影不影响连接复用？
// Go 1.27 起 Transport 会在 Close 时尝试异步排空 body（上限 256 KiB / 50 ms）。
// 这组探针把 6 种写法逐一跑出来，看第二条请求有没有复用同一条 TCP 连接。
package main

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"strings"
	"sync"
	"time"
)

// ---- 服务端连接状态统计（用来数“客户端还攥着几条空闲连接”）----
var (
	connMu    sync.Mutex
	connState = map[net.Conn]http.ConnState{}
	accepted  int
)

func countState(want http.ConnState) int {
	connMu.Lock()
	defer connMu.Unlock()
	n := 0
	for _, s := range connState {
		if s == want {
			n++
		}
	}
	return n
}

func newConn() { connMu.Lock(); accepted++; connMu.Unlock() }

func mustServer() (*http.Server, string) {
	mux := http.NewServeMux()
	// 4 KiB：小 body，远低于 256 KiB 阈值
	mux.HandleFunc("/small", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		io.WriteString(w, strings.Repeat("a", 4<<10))
	})
	// 1 MiB：大 body，超过 256 KiB 阈值
	mux.HandleFunc("/big", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		io.WriteString(w, strings.Repeat("b", 1<<20))
	})
	// 128 KiB 但发得慢（总共约 400 ms）：总量低于阈值，但排空时间超过 50 ms
	mux.HandleFunc("/dribble", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(200)
		f := w.(http.Flusher)
		chunk := bytes.Repeat([]byte("c"), 8<<10) // 8 KiB
		for i := 0; i < 16; i++ {                 // 共 128 KiB
			if _, err := w.Write(chunk); err != nil {
				return // 客户端已经走了
			}
			f.Flush()
			time.Sleep(25 * time.Millisecond) // 16 × 25 ms = 400 ms
		}
	})
	// 服务端明确要求关连接
	mux.HandleFunc("/close", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Connection", "close")
		io.WriteString(w, "bye")
	})
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	srv := &http.Server{
		Handler: mux,
		ConnState: func(c net.Conn, s http.ConnState) {
			connMu.Lock()
			if s == http.StateClosed || s == http.StateHijacked {
				delete(connState, c)
			} else {
				if _, seen := connState[c]; !seen {
					accepted++
				}
				connState[c] = s
			}
			connMu.Unlock()
		},
	}
	go srv.Serve(ln)
	return srv, "http://" + ln.Addr().String()
}

type reuse struct {
	reused    bool
	connLocal string
}

// 用专属 Transport 连发两条请求，看第二条有没有复用连接
func probe(base, path string, consume func(*http.Response) error) (reuse, error) {
	tr := &http.Transport{} // 全新 Transport，池是干净的
	defer tr.CloseIdleConnections()
	c := &http.Client{Transport: tr, Timeout: 5 * time.Second}

	do := func() (reuse, error) {
		var got reuse
		trace := &httptrace.ClientTrace{
			GotConn: func(info httptrace.GotConnInfo) {
				got = reuse{reused: info.Reused, connLocal: info.Conn.LocalAddr().String()}
			},
		}
		req, _ := http.NewRequest(http.MethodGet, base+path, nil)
		req = req.WithContext(httptrace.WithClientTrace(req.Context(), trace))
		resp, err := c.Do(req)
		if err != nil {
			return got, err
		}
		if consume != nil {
			if err := consume(resp); err != nil {
				resp.Body.Close()
				return got, err
			}
		}
		return got, resp.Body.Close()
	}

	if _, err := do(); err != nil { // 第一条：建连接
		return reuse{}, err
	}
	return do() // 第二条：看是否复用
}

func main() {
	srv, base := mustServer()
	defer srv.Close()
	fmt.Printf("本地服务：%s\n", base)
	fmt.Println("判定方式：连发两条请求，看第二条的 httptrace.GotConnInfo.Reused")

	readAll := func(resp *http.Response) error { _, err := io.Copy(io.Discard, resp.Body); return err }
	justClose := func(resp *http.Response) error { return nil } // 不读，留给 Close

	cases := []struct {
		name    string
		path    string
		consume func(*http.Response) error
	}{
		{"A 读到 EOF 再 Close      /small  (4 KiB)", "/small", readAll},
		{"B 不读直接 Close         /small  (4 KiB)", "/small", justClose},
		{"C 不读直接 Close         /big    (1 MiB)", "/big", justClose},
		{"D 不读直接 Close         /dribble(128 KiB / 400ms)", "/dribble", justClose},
		{"E 先 Copy 到 EOF 再 Close /big    (1 MiB)", "/big", readAll},
		{"F 读完再 Close，服务端 Connection: close", "/close", readAll},
	}

	fmt.Println()
	for _, c := range cases {
		r, err := probe(base, c.path, c.consume)
		status := "❌ 没复用（新连接）"
		if r.reused {
			status = "✅ 复用了同一条连接"
		}
		extra := ""
		if err != nil {
			extra = fmt.Sprintf("   err=%v", err)
		}
		fmt.Printf("%-52s → %s%s\n", c.name, status, extra)
	}

	// ---- G：MaxIdleConnsPerHost 的影响 ----
	fmt.Println()
	fmt.Println("G) MaxIdleConnsPerHost 默认 2：并发 5 条 /big（读完整）之后池里留几条")
	for _, perHost := range []int{0, 5} {
		tr := &http.Transport{MaxIdleConnsPerHost: perHost}
		c := &http.Client{Transport: tr, Timeout: 5 * time.Second}
		beforeAccepted := func() int { connMu.Lock(); defer connMu.Unlock(); return accepted }()
		var wg sync.WaitGroup
		for i := 0; i < 5; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				resp, err := c.Get(base + "/big")
				if err != nil {
					return
				}
				io.Copy(io.Discard, resp.Body)
				resp.Body.Close()
			}()
		}
		wg.Wait()
		time.Sleep(150 * time.Millisecond)
		afterAccepted := func() int { connMu.Lock(); defer connMu.Unlock(); return accepted }()
		label := fmt.Sprintf("MaxIdleConnsPerHost=%d", perHost)
		if perHost == 0 {
			label += "（=默认 2）"
		}
		fmt.Printf("   %-30s 新建 TCP 连接 %d 条，服务端仍处于 idle 的连接 %d 条\n",
			label, afterAccepted-beforeAccepted, countState(http.StateIdle))
		tr.CloseIdleConnections()
		time.Sleep(150 * time.Millisecond)
	}

	// ---- H：Close 本身很快，排空在后台 ----
	fmt.Println()
	fmt.Println("H) 时序：不读直接 Close，调用本身多久返回")
	tr := &http.Transport{}
	c := &http.Client{Transport: tr, Timeout: 5 * time.Second}
	resp, err := c.Get(base + "/dribble")
	if err != nil {
		panic(err)
	}
	t0 := time.Now()
	_ = resp.Body.Close() // 不读
	fmt.Printf("   Close() 调用耗时 %v（同步返回很快，排空在后台 goroutine 里做）\n",
		time.Since(t0).Round(time.Microsecond))
	time.Sleep(120 * time.Millisecond)
	fmt.Printf("   120ms 后服务端 idle 连接 %d 条（dribble 要 400ms 才发完，排空在 50ms 就被判失败）\n",
		countState(http.StateIdle))
	tr.CloseIdleConnections()
}

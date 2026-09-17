// p10_retry —— 重试的边界：只对幂等请求重试、必须退避、重试前要把 body 处理干净；
// 以及 Transport 的连接上限（MaxConnsPerHost）与「复用 Client」的收益。
package main

import (
	"context"
	"fmt"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

var (
	flakyHits   atomic.Int64
	retryHits   atomic.Int64
	accepted    atomic.Int64
	activeConns atomic.Int64
	peakConns   atomic.Int64
)

func bumpPeak(v int64) {
	for {
		p := peakConns.Load()
		if v <= p || peakConns.CompareAndSwap(p, v) {
			return
		}
	}
}

func mustServer() (*http.Server, string) {
	mux := http.NewServeMux()
	// 前 2 次返回 503，第 3 次起 200
	mux.HandleFunc("/flaky", func(w http.ResponseWriter, r *http.Request) {
		n := flakyHits.Add(1)
		if n <= 2 {
			w.Header().Set("Retry-After", "1")
			w.WriteHeader(http.StatusServiceUnavailable)
			io.WriteString(w, `{"error":"上游暂时不可用"}`)
			return
		}
		io.WriteString(w, `{"ok":true,"attempt":`+fmt.Sprint(n)+`}`)
	})
	// 每次都 503
	mux.HandleFunc("/always503", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
		io.WriteString(w, `{"error":"一直不可用"}`)
	})
	// 慢接口，用来演示连接上限
	mux.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(200 * time.Millisecond)
		io.WriteString(w, "ok")
	})
	// 计数接口：用来演示「复用 Client」能省多少 TCP 连接
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "pong")
	})
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	srv := &http.Server{
		Handler: mux,
		ConnState: func(c net.Conn, s http.ConnState) {
			switch s {
			case http.StateNew:
				accepted.Add(1)
				n := activeConns.Add(1)
				bumpPeak(n)
			case http.StateClosed, http.StateHijacked:
				activeConns.Add(-1)
			}
		},
	}
	go srv.Serve(ln)
	return srv, "http://" + ln.Addr().String()
}

// 带退避的重试：只对幂等方法 + 可重试状态码
type attemptLog struct {
	n        int
	status   int
	err      error
	waited   time.Duration
	total    time.Duration
	retrying bool
}

func doWithRetry(c *http.Client, method, url string, maxAttempts int) ([]attemptLog, string) {
	var out []attemptLog
	start := time.Now()
	backoff := 80 * time.Millisecond
	var lastBody string
	for i := 1; i <= maxAttempts; i++ {
		var waited time.Duration
		req, _ := http.NewRequest(method, url, nil)
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		req = req.WithContext(ctx)
		resp, err := c.Do(req)
		rec := attemptLog{n: i, err: err, total: time.Since(start)}
		if err != nil {
			cancel()
			out = append(out, rec)
			break
		}
		b, _ := io.ReadAll(resp.Body) // 重试前必须把 body 读干净
		resp.Body.Close()
		cancel()
		rec.status = resp.StatusCode
		lastBody = string(b)

		retryable := resp.StatusCode == http.StatusTooManyRequests ||
			(resp.StatusCode >= 500 && resp.StatusCode <= 599)
		// 幂等方法才允许重试：GET / HEAD / PUT / DELETE / OPTIONS / TRACE
		idempotent := method == http.MethodGet || method == http.MethodHead ||
			method == http.MethodPut || method == http.MethodDelete

		if !retryable || !idempotent || i == maxAttempts {
			out = append(out, rec)
			break
		}
		// 指数退避 + 抖动
		jitter := time.Duration(rand.Int64N(int64(backoff / 2)))
		waited = backoff + jitter
		rec.retrying = true
		rec.waited = waited
		out = append(out, rec)
		time.Sleep(waited)
		backoff *= 2
	}
	return out, lastBody
}

func main() {
	srv, base := mustServer()
	defer srv.Close()
	fmt.Printf("本地服务：%s\n\n", base)

	client := &http.Client{Timeout: 3 * time.Second}

	// ---------------------------------------------------------------- 1
	fmt.Println("1) GET /flaky（前两次 503，第三次 200）：带退避重试")
	logs, body := doWithRetry(client, http.MethodGet, base+"/flaky", 5)
	for _, l := range logs {
		if l.retrying {
			fmt.Printf("   第 %d 次 → %d，退避 %v 后重试（累计 %v）\n",
				l.n, l.status, l.waited.Round(time.Millisecond), l.total.Round(time.Millisecond))
		} else {
			fmt.Printf("   第 %d 次 → %d，放弃重试（累计 %v）\n",
				l.n, l.status, l.total.Round(time.Millisecond))
		}
	}
	fmt.Printf("   最终 body = %s\n\n", body)

	// ---------------------------------------------------------------- 2
	fmt.Println("2) 同样重试逻辑用在 POST 上：不重试（方法不幂等）")
	flakyHits.Store(0)
	logs2, body2 := doWithRetry(client, http.MethodPost, base+"/flaky", 5)
	for _, l := range logs2 {
		fmt.Printf("   第 %d 次 → %d  retrying=%v（累计 %v）\n",
			l.n, l.status, l.retrying, l.total.Round(time.Millisecond))
	}
	fmt.Printf("   最终 body = %s ← 一次就放弃了\n\n", strings.TrimSpace(body2))

	// ---------------------------------------------------------------- 3
	fmt.Println("3) 一直 503：重试上限必须存在，否则就是放大器")
	logs3, _ := doWithRetry(client, http.MethodGet, base+"/always503", 4)
	fmt.Printf("   一共打了 %d 次，退避序列：", len(logs3))
	first := true
	for _, l := range logs3 {
		if l.waited <= 0 {
			continue
		}
		if !first {
			fmt.Print(" → ")
		}
		first = false
		fmt.Printf("%v", l.waited.Round(time.Millisecond))
	}
	fmt.Printf("，总耗时 %v\n\n", logs3[len(logs3)-1].total.Round(time.Millisecond))

	// ---------------------------------------------------------------- 4
	fmt.Println("4) Transport.MaxConnsPerHost 把并发连接卡住")
	var prev *http.Transport
	for _, maxConns := range []int{0, 2} {
		if prev != nil { // 清掉上一轮残留的空闲连接，保证这轮是「冷启动」
			prev.CloseIdleConnections()
			time.Sleep(150 * time.Millisecond)
		}
		tr := &http.Transport{MaxConnsPerHost: maxConns}
		prev = tr
		accepted.Store(0)
		activeConns.Store(0)
		peakConns.Store(0)
		c := &http.Client{Transport: tr, Timeout: 5 * time.Second}
		t0 := time.Now()
		var wg sync.WaitGroup
		for i := 0; i < 6; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				resp, err := c.Get(base + "/slow")
				if err != nil {
					return
				}
				io.Copy(io.Discard, resp.Body)
				resp.Body.Close()
			}()
		}
		wg.Wait()
		label := fmt.Sprintf("MaxConnsPerHost=%d", maxConns)
		if maxConns == 0 {
			label += "（默认：不限）"
		}
		fmt.Printf("   %-28s 6 个并发慢请求，总耗时 %v，新建连接 %d 条，峰值并发连接 %d\n",
			label, time.Since(t0).Round(time.Millisecond), accepted.Load(), peakConns.Load())
	}
	if prev != nil {
		prev.CloseIdleConnections()
		time.Sleep(150 * time.Millisecond)
	}
	fmt.Println()

	// ---------------------------------------------------------------- 5
	fmt.Println("5) 复用 Client vs 每次都新建 Transport（各 100 次请求）")
	sharedTr := &http.Transport{}
	sharedTr.CloseIdleConnections()
	time.Sleep(150 * time.Millisecond)
	accepted.Store(0)
	shared := &http.Client{Transport: sharedTr, Timeout: 3 * time.Second}
	for i := 0; i < 100; i++ {
		resp, err := shared.Get(base + "/ping")
		if err != nil {
			fmt.Println("   err:", err)
			break
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
	fmt.Printf("   共用同一个 Client：服务端新建 TCP 连接 %d 条\n", accepted.Load())

	sharedTr.CloseIdleConnections()
	time.Sleep(150 * time.Millisecond)
	accepted.Store(0)
	for i := 0; i < 100; i++ {
		c := &http.Client{Transport: &http.Transport{}, Timeout: 3 * time.Second}
		resp, err := c.Get(base + "/ping")
		if err != nil {
			fmt.Println("   err:", err)
			break
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		c.CloseIdleConnections()
	}
	fmt.Printf("   每次新建 Client+Transport：服务端新建 TCP 连接 %d 条\n", accepted.Load())
}

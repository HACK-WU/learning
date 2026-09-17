// package main —— 知识点 2 的完整示例：一个"生产级"下游客户端封装
//
//	超时 / 必读必关 body / 连接池参数 / 只在幂等请求上做有上限的退避重试
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

// ============ ① 下游服务（模拟库存 / 风控服务） ============

type server struct {
	mux       *http.ServeMux
	mu        sync.Mutex
	connState map[net.Conn]http.ConnState
	newConns  int64
	getHit    int64
	postHit   int64
}

func newServer() *server {
	s := &server{mux: http.NewServeMux(), connState: map[net.Conn]http.ConnState{}}

	// GET：前两次 503，第三次 200 —— 用来验证"幂等重试"
	s.mux.HandleFunc("/flaky", func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt64(&s.getHit, 1)
		if n <= 2 {
			w.WriteHeader(http.StatusServiceUnavailable)
			io.WriteString(w, `{"error":"上游暂时不可用"}`)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"ok":true,"attempt":%d}`, n)
	})

	// POST：永远 503 —— 用来验证"不幂等就不重试"
	s.mux.HandleFunc("/flaky-post", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt64(&s.postHit, 1)
		w.WriteHeader(http.StatusServiceUnavailable)
		io.WriteString(w, `{"error":"上游暂时不可用"}`)
	})

	// 1 MiB 响应体 —— 用来验证"读完之后才能复用"
	s.mux.HandleFunc("/big", func(w http.ResponseWriter, r *http.Request) {
		w.Write(make([]byte, 1<<20))
	})

	// 慢响应 —— 用来验证客户端超时
	s.mux.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-time.After(800 * time.Millisecond):
		case <-r.Context().Done():
			return
		}
		io.WriteString(w, "慢响应终于来了")
	})

	// 回显方法 —— 小请求，用来数连接
	s.mux.HandleFunc("/echo", func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		fmt.Fprintf(w, `{"method":"%s","len":%d}`, r.Method, len(b))
	})

	return s
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

func (s *server) ConnState(c net.Conn, st http.ConnState) {
	if st == http.StateNew {
		atomic.AddInt64(&s.newConns, 1)
	}
	s.mu.Lock()
	s.connState[c] = st
	s.mu.Unlock()
}

func (s *server) NewConns() int64 { return atomic.LoadInt64(&s.newConns) }

func (s *server) IdleConns() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for _, st := range s.connState {
		if st == http.StateIdle {
			n++
		}
	}
	return n
}

// ============ ② 生产级客户端封装 ============

// Downstream 是一个复用的下游客户端。★ 全进程一个实例，绝不每请求新建。
type Downstream struct {
	c          *http.Client
	maxAttempt int
	baseDelay  time.Duration
}

func NewDownstream() *Downstream {
	tr := &http.Transport{
		// 连接池：这里全部显式设，不依赖默认值
		MaxIdleConns:        100,              // 跨主机空闲连接总量（DefaultTransport 也是 100）
		MaxIdleConnsPerHost: 10,               // ★ 默认只有 2，并发一高就不够
		MaxConnsPerHost:     20,               // ★ 默认 0（不限）—— 要"给自己封顶"时设它
		IdleConnTimeout:     90 * time.Second, // 与 DefaultTransport 一致
		// 建连与 TLS 超时（DefaultTransport 里也是这两个值）
		DialContext:         (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout: 10 * time.Second,
	}
	return &Downstream{
		// ★ 超时必须显式设：默认 Client 的 Timeout 是 0 = 永不超时
		c:          &http.Client{Timeout: 2 * time.Second, Transport: tr},
		maxAttempt: 3,
		baseDelay:  80 * time.Millisecond,
	}
}

// idempotent 只有幂等方法才允许重试。★ 这是重试的第一道闸门
func idempotent(method string) bool {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPut, http.MethodDelete, http.MethodOptions:
		return true
	}
	return false
}

// Resp 是封装后返回给业务的东西：body 已经读进内存了，调用方不用管 Close
type Resp struct {
	Status int
	Body   []byte
}

// Do 发一次请求，按需重试。返回 (Resp, 尝试次数, error)
func (d *Downstream) Do(ctx context.Context, method, url string, body io.Reader) (*Resp, int, error) {
	var lastErr error

	for attempt := 1; attempt <= d.maxAttempt; attempt++ {
		req, err := http.NewRequestWithContext(ctx, method, url, body)
		if err != nil {
			return nil, attempt, err
		}

		resp, err := d.c.Do(req)
		if err != nil {
			lastErr = err
			// ★ 重试之前必须先看 ctx：已经取消了就别再打了
			if ctx.Err() != nil {
				return nil, attempt, err
			}
			// 网络层错误（含超时）可以重试 —— 但必须满足幂等 + 还有次数
			if !idempotent(method) || attempt == d.maxAttempt {
				return nil, attempt, err
			}
			d.backoff(ctx, attempt)
			continue
		}

		// ★ 无论后续怎么处理，body 都必须关；小 body 顺便读干
		b, readErr := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
		closeErr := resp.Body.Close()
		if readErr != nil {
			return nil, attempt, fmt.Errorf("读 body: %w", readErr)
		}
		_ = closeErr

		// 5xx 才重试；4xx 是"你的错"，重试没意义
		if resp.StatusCode >= 500 && idempotent(method) && attempt < d.maxAttempt {
			lastErr = fmt.Errorf("上游返回 %d", resp.StatusCode)
			d.backoff(ctx, attempt)
			continue
		}

		return &Resp{Status: resp.StatusCode, Body: b}, attempt, nil
	}
	return nil, d.maxAttempt, lastErr
}

// backoff 指数退避 + 抖动，且必须能被 ctx 打断
func (d *Downstream) backoff(ctx context.Context, attempt int) {
	delay := d.baseDelay * time.Duration(1<<(attempt-1))
	delay += time.Duration(rand.Int63n(int64(d.baseDelay))) // 抖动，避免惊群
	select {
	case <-time.After(delay):
	case <-ctx.Done():
	}
}

// Close 清空连接池（发布 / 切流量时用）
func (d *Downstream) Close() {
	if tr, ok := d.c.Transport.(*http.Transport); ok {
		tr.CloseIdleConnections()
	}
}

// ============ ③ 演示 ============

func main() {
	srv := newServer()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	hs := &http.Server{Handler: srv, ConnState: srv.ConnState}
	go hs.Serve(ln)
	defer hs.Close()

	base := "http://" + ln.Addr().String()
	d := NewDownstream()
	defer d.Close()

	ctx := context.Background()

	// 1) GET 幂等 → 会重试
	fmt.Println("1) GET /flaky（前两次 503，第三次 200）—— 幂等，允许重试")
	r, n, err := d.Do(ctx, http.MethodGet, base+"/flaky", nil)
	if err != nil {
		fmt.Printf("   err=%v\n", err)
	} else {
		fmt.Printf("   状态=%d body=%s 共尝试 %d 次\n", r.Status, r.Body, n)
	}

	// 2) POST 不幂等 → 不重试
	fmt.Println("\n2) POST /flaky-post（服务端永远 503）—— 不幂等，一次就放弃")
	r, n, err = d.Do(ctx, http.MethodPost, base+"/flaky-post", nil)
	if err != nil {
		fmt.Printf("   err=%v\n", err)
	} else {
		fmt.Printf("   状态=%d body=%s 共尝试 %d 次（服务端被打了几次：%d）\n",
			r.Status, r.Body, n, atomic.LoadInt64(&srv.postHit))
	}

	// 3) 连接复用基线：先清空池子，再连打 2 条小请求
	d.Close()
	time.Sleep(60 * time.Millisecond)
	before := srv.NewConns()
	for i := 0; i < 2; i++ {
		if _, _, err := d.Do(ctx, http.MethodGet, base+"/echo", nil); err != nil {
			fmt.Printf("   err=%v\n", err)
		}
	}
	fmt.Printf("\n3) 清空池子后连打 2 条 /echo：新建 TCP 连接 %d 条（第 2 条复用了第 1 条）\n",
		srv.NewConns()-before)

	// 4) 大 body 读完之后也复用
	before = srv.NewConns()
	for i := 0; i < 2; i++ {
		if _, _, err := d.Do(ctx, http.MethodGet, base+"/big", nil); err != nil {
			fmt.Printf("   err=%v\n", err)
		}
	}
	fmt.Printf("4) 连打 2 条 /big（1 MiB，读完并关闭）：新建 TCP 连接 %d 条\n", srv.NewConns()-before)

	// 5) 客户端超时：ctx 200ms 比 Client.Timeout 2s 更早
	fmt.Println("\n5) /slow（服务端睡 800ms）：ctx 200ms vs Client.Timeout 2s，谁更早谁说了算")
	tctx, cancel := context.WithTimeout(ctx, 200*time.Millisecond)
	defer cancel()
	t0 := time.Now()
	_, n, err = d.Do(tctx, http.MethodGet, base+"/slow", nil)
	fmt.Printf("   尝试 %d 次，耗时约 %v，err=%v\n", n, time.Since(t0).Round(time.Millisecond), err)
	fmt.Printf("   errors.Is(err, context.DeadlineExceeded)=%v\n", errors.Is(err, context.DeadlineExceeded))

	// 6) 池子的形状与清空
	fmt.Println("\n6) 并发 3 条 /hold（各占 100ms）—— 池子会长成什么样，以及怎么清空")
	d.Close()
	time.Sleep(60 * time.Millisecond)
	before = srv.NewConns()
	var wg sync.WaitGroup
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, _, _ = d.Do(ctx, http.MethodGet, base+"/hold", nil)
		}()
	}
	wg.Wait()
	fmt.Printf("   新建 TCP 连接 %d 条；请求做完后服务端 idle 连接 %d 条\n",
		srv.NewConns()-before, srv.IdleConns())
	d.Close()
	time.Sleep(100 * time.Millisecond)
	fmt.Printf("   CloseIdleConnections() 之后 idle 连接 %d 条\n", srv.IdleConns())
}

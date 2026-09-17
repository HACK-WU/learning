// p8_client_timeout —— http.Client 的超时与 DefaultTransport 的真实参数。
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

func newLocalServer() (*http.Server, string) {
	mux := http.NewServeMux()
	// 慢响应：连上后先睡 2 秒才回
	mux.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(2 * time.Second)
		fmt.Fprintln(w, "慢响应终于来了")
	})
	// 头很快、body 很慢：用来证明 Client.Timeout 覆盖“读 body”
	mux.HandleFunc("/slowbody", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(200)
		for i := 0; i < 20; i++ {
			fmt.Fprintf(w, "chunk-%02d\n", i)
			if f, ok := w.(http.Flusher); ok {
				f.Flush()
			}
			time.Sleep(200 * time.Millisecond)
		}
	})
	mux.HandleFunc("/fast", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	srv := &http.Server{Handler: mux}
	go srv.Serve(ln)
	return srv, "http://" + ln.Addr().String()
}

func main() {
	srv, base := newLocalServer()
	defer srv.Close()
	fmt.Printf("本地服务：%s\n\n", base)

	// ---------------------------------------------------------------- 1
	fmt.Println("1) 默认 http.Get —— Timeout 字段是 0，等于“永不超时”")
	fmt.Printf("   DefaultClient.Timeout = %v\n", http.DefaultClient.Timeout)
	t0 := time.Now()
	resp, err := http.Get(base + "/slow")
	if err != nil {
		fmt.Println("   err:", err)
	} else {
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		fmt.Printf("   耗时 %v，body=%q ← 硬等了 2 秒，没人拦得住\n",
			time.Since(t0).Round(time.Millisecond), strings.TrimSpace(string(b)))
	}
	fmt.Println()

	// ---------------------------------------------------------------- 2
	fmt.Println("2) Client{Timeout: 300ms} —— 300 毫秒后主动放弃")
	c := &http.Client{Timeout: 300 * time.Millisecond}
	t1 := time.Now()
	resp, err = c.Get(base + "/slow")
	fmt.Printf("   耗时 %v\n   err = %v\n", time.Since(t1).Round(time.Millisecond), err)
	var uerr *url.Error
	if errors.As(err, &uerr) {
		fmt.Printf("   err.(*url.Error).Timeout() = %v\n", uerr.Timeout())
		fmt.Printf("   errors.Is(err, context.DeadlineExceeded) = %v\n",
			errors.Is(err, context.DeadlineExceeded))
	}
	fmt.Println()

	// ---------------------------------------------------------------- 3
	fmt.Println("3) Client.Timeout 覆盖“读 body”：头 1ms 就回来了，body 要 4 秒")
	t2 := time.Now()
	resp, err = c.Get(base + "/slowbody")
	if err != nil {
		fmt.Printf("   请求阶段就失败：%v\n", err)
	} else {
		fmt.Printf("   拿到响应头，耗时 %v，状态 %s\n", time.Since(t2).Round(time.Millisecond), resp.Status)
		n, rerr := io.Copy(io.Discard, resp.Body)
		fmt.Printf("   读 body 时被掐断：读了 %d 字节，err = %v，总耗时 %v\n",
			n, rerr, time.Since(t2).Round(time.Millisecond))
		resp.Body.Close()
	}
	fmt.Println()

	// ---------------------------------------------------------------- 4
	fmt.Println("4) 用 context 控超时（Client.Timeout 之外的另一条路）")
	ctx, cancel := context.WithTimeout(context.Background(), 250*time.Millisecond)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+"/slow", nil)
	t3 := time.Now()
	resp, err = (&http.Client{}).Do(req)
	fmt.Printf("   耗时 %v  err = %v\n", time.Since(t3).Round(time.Millisecond), err)
	if resp != nil {
		resp.Body.Close()
	}
	fmt.Println()

	// ---------------------------------------------------------------- 5
	fmt.Println("5) DefaultTransport 的真实字段值")
	tr, ok := http.DefaultTransport.(*http.Transport)
	fmt.Printf("   DefaultTransport 是 *http.Transport：%v\n", ok)
	fmt.Printf("   Proxy               = %T（ProxyFromEnvironment）\n", tr.Proxy)
	fmt.Printf("   ForceAttemptHTTP2   = %v（注意：DefaultTransport 里显式打开了）\n", tr.ForceAttemptHTTP2)
	fmt.Printf("   MaxIdleConns        = %v\n", tr.MaxIdleConns)
	fmt.Printf("   MaxIdleConnsPerHost = %v ← 未设置，所以用常量 %v\n",
		tr.MaxIdleConnsPerHost, http.DefaultMaxIdleConnsPerHost)
	fmt.Printf("   IdleConnTimeout     = %v\n", tr.IdleConnTimeout)
	fmt.Printf("   TLSHandshakeTimeout = %v\n", tr.TLSHandshakeTimeout)
	fmt.Printf("   ExpectContinueTimeout = %v\n", tr.ExpectContinueTimeout)
	fmt.Printf("   DisableKeepAlives   = %v\n", tr.DisableKeepAlives)
	fmt.Printf("   DisableCompression  = %v\n", tr.DisableCompression)
	fmt.Println()

	// ---------------------------------------------------------------- 6
	fmt.Println("6) 环境变量里的代理会不会把 127.0.0.1 也带走？")
	for _, k := range []string{"HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy"} {
		if v := os.Getenv(k); v != "" {
			fmt.Printf("   %-12s = %s\n", k, v)
		}
	}
	proxyURL, perr := http.ProxyFromEnvironment(&http.Request{URL: mustURL(base + "/fast")})
	fmt.Printf("   ProxyFromEnvironment(本地地址) → %v, err=%v\n", proxyURL, perr)
	cProxy := &http.Client{Timeout: 2 * time.Second} // 用 DefaultTransport，也就是含 ProxyFromEnvironment
	t4 := time.Now()
	resp, err = cProxy.Get(base + "/fast")
	if err != nil {
		fmt.Printf("   走默认 Transport 访问本地：err = %v（耗时 %v）\n",
			err, time.Since(t4).Round(time.Millisecond))
	} else {
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		fmt.Printf("   走默认 Transport 访问本地：成功，body=%q（耗时 %v）\n",
			strings.TrimSpace(string(b)), time.Since(t4).Round(time.Millisecond))
	}
	// 显式关掉代理再试一次
	cNoProxy := &http.Client{
		Timeout:   2 * time.Second,
		Transport: &http.Transport{Proxy: nil},
	}
	t5 := time.Now()
	resp, err = cNoProxy.Get(base + "/fast")
	if err != nil {
		fmt.Printf("   Transport{Proxy: nil} 访问本地：err = %v（耗时 %v）\n",
			err, time.Since(t5).Round(time.Millisecond))
	} else {
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		fmt.Printf("   Transport{Proxy: nil} 访问本地：成功，body=%q（耗时 %v）\n",
			strings.TrimSpace(string(b)), time.Since(t5).Round(time.Millisecond))
	}
}

func mustURL(s string) *url.URL {
	u, err := url.Parse(s)
	if err != nil {
		panic(err)
	}
	return u
}

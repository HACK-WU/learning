// p5_ctx_chain —— 把课 11 的取消链路接进 database/sql：
//
//	客户端断开 → net/http 取消 r.Context() → db.QueryRowContext 感知 → 查询中止
//
// 这个包自带一个 HTTP 服务和一个会中途取消的客户端，一次 go run 跑完全链。
package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

// 一条“慢查询”：递归 CTE 累加到 n，n=2_000_000 大约 1.4 秒
func slowQuery(n int) string {
	return fmt.Sprintf(
		`WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x < %d) SELECT COUNT(*) FROM c`, n)
}

const slowN = 6000000 // 约 3~5 秒（随机器负载波动）

var (
	logMu sync.Mutex
	logs  []string
)

func serverLog(format string, a ...any) {
	line := fmt.Sprintf("[服务端 %s] %s", time.Now().Format("15:04:05.000"), fmt.Sprintf(format, a...))
	logMu.Lock()
	logs = append(logs, line)
	logMu.Unlock()
	fmt.Println(line)
}

func dumpLogs() {
	logMu.Lock()
	defer logMu.Unlock()
	fmt.Println("---- 服务端日志汇总 ----")
	for _, l := range logs {
		fmt.Println("  " + l)
	}
	fmt.Println()
	logs = logs[:0]
}

func main() {
	dir, _ := os.MkdirTemp("", "l12ctx")
	defer os.RemoveAll(dir)
	db, err := sql.Open("sqlite", filepath.Join(dir, "q.db"))
	if err != nil {
		panic(err)
	}
	defer db.Close()
	db.SetMaxOpenConns(4)

	var cnt int
	if err := db.QueryRow(slowQuery(10000)).Scan(&cnt); err != nil {
		panic(err)
	}

	// ---------------------------------------------------------------- 1
	fmt.Println("1) QueryRowContext + 300ms 超时（直接看 sql 层）")
	start := time.Now()
	ctxA, cancelA := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancelA()
	errA := db.QueryRowContext(ctxA, slowQuery(slowN)).Scan(&cnt)
	fmt.Printf("   耗时 %v  err = %v\n", time.Since(start).Round(time.Millisecond), errA)
	fmt.Printf("   errors.Is(err, context.DeadlineExceeded) = %v\n",
		errors.Is(errA, context.DeadlineExceeded))
	fmt.Println()

	// ---------------------------------------------------------------- 2
	fmt.Println("2) 对照：QueryRow（不带 ctx）——没人能叫停它")
	start2 := time.Now()
	err2 := db.QueryRow(slowQuery(2000000)).Scan(&cnt)
	fmt.Printf("   耗时 %v  err = %v  count = %d（跑完了）\n", time.Since(start2).Round(time.Millisecond), err2, cnt)
	fmt.Println()

	// ---------------------------------------------------------------- 3
	fmt.Println("3) 全链路：客户端中途断开 → r.Context() 取消 → 查询中止")

	mux := http.NewServeMux()
	mux.HandleFunc("/orders/ctx", func(w http.ResponseWriter, r *http.Request) {
		serverLog("收到请求 %s，handler 开始跑慢查询（递归 CTE，数秒量级）", r.URL.Path)
		t0 := time.Now()
		var n int
		err := db.QueryRowContext(r.Context(), slowQuery(slowN)).Scan(&n)
		serverLog("查询返回：err=%v 耗时=%v", err, time.Since(t0).Round(time.Millisecond))
		if err != nil {
			// 客户端已经走了，这里写不回任何东西
			return
		}
		fmt.Fprintf(w, "count=%d\n", n)
	})
	mux.HandleFunc("/orders/nocancel", func(w http.ResponseWriter, r *http.Request) {
		serverLog("收到请求 %s，handler 用 QueryRow（忽略 ctx）", r.URL.Path)
		t0 := time.Now()
		var n int
		err := db.QueryRow(slowQuery(slowN)).Scan(&n) // 故意不传 ctx
		serverLog("查询返回：err=%v 耗时=%v", err, time.Since(t0).Round(time.Millisecond))
		fmt.Fprintf(w, "count=%d\n", n)
	})

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	srv := &http.Server{Handler: mux}
	go srv.Serve(ln)
	defer srv.Close()
	base := "http://" + ln.Addr().String()
	fmt.Printf("   服务已起：%s\n", base)

	// 客户端 400ms 后主动取消（模拟用户关掉页面 / 手机断网）
	client := &http.Client{}
	hit := func(path string, after time.Duration) {
		ctx, cancel := context.WithTimeout(context.Background(), after)
		defer cancel()
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+path, nil)
		t0 := time.Now()
		resp, err := client.Do(req)
		if err != nil {
			fmt.Printf("   客户端 %s 在 %v 后放弃 → err = %v\n", path, time.Since(t0).Round(time.Millisecond), err)
			return
		}
		defer resp.Body.Close()
		fmt.Printf("   客户端 %s 成功，状态 %s\n", path, resp.Status)
	}

	fmt.Println("   3a) /orders/ctx：客户端 400ms 就放弃")
	hit("/orders/ctx", 400*time.Millisecond)
	time.Sleep(600 * time.Millisecond) // 等服务端 handler 收尾
	dumpLogs()

	fmt.Println("   3b) /orders/nocancel：客户端同样 400ms 放弃，但 handler 忽略了 ctx")
	hit("/orders/nocancel", 400*time.Millisecond)
	time.Sleep(2600 * time.Millisecond)
	dumpLogs()

	fmt.Println("   结论：3a 里查询在客户端放弃的同一瞬间被 ctx 掐断（约 0.4 秒）；")
	fmt.Println("         3b 里同一条查询完整跑完（耗时见上方服务端日志），没有人能叫停它。")
}

// package main —— 知识点 3 的完整示例：时间与定时器
//
//	① 定时任务骨架（Ticker + ctx 收口 + Stop）
//	② 热路径上 time.After vs 复用 Timer 的累计分配
//	③ 订单时间戳的格式化与解析（含布局串、两位年、时区、AddDate 月末回绕）
//	④ 单调时钟陷阱现场
package main

import (
	"context"
	"fmt"
	"runtime"
	"time"
)

// ============ ① 服务端定时任务骨架 ============

// RunPeriodic 每 period 跑一次 job，直到 ctx 取消。
// ★ 三个纪律：Ticker 必须 Stop；用 select 同时看 ctx 和 tick；
//
//	job 的耗时要算出来，否则"慢 job"会吃掉整个周期。
func RunPeriodic(ctx context.Context, period time.Duration, maxRuns int, job func(run int, drift time.Duration)) int {
	t := time.NewTicker(period)
	defer t.Stop() // ★ 无论怎么返回都要 Stop

	start := time.Now()
	runs := 0
	for {
		select {
		case <-ctx.Done():
			return runs
		case tick := <-t.C:
			runs++
			// ★ 用 Since 算真实间隔，而不是自己累加 period
			job(runs, time.Since(start))
			if maxRuns > 0 && runs >= maxRuns {
				return runs
			}
			_ = tick
		}
	}
}

// ============ ② 热路径：After vs 复用 Timer ============

func allocPerLoop(kind string, n int) uint64 {
	var a, b runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&a)

	switch kind {
	case "after":
		for i := 0; i < n; i++ {
			_ = time.After(time.Hour) // 每次新建一个定时器
		}
	case "reuse":
		t := time.NewTimer(time.Hour)
		for i := 0; i < n; i++ {
			t.Reset(time.Hour) // 复用同一个
			_ = t.C
		}
		t.Stop()
	}

	runtime.ReadMemStats(&b)
	return b.TotalAlloc - a.TotalAlloc
}

// ============ ③ 格式化与解析 ============

const (
	LayoutOrder   = "2006-01-02 15:04:05" // 业务里最常用的这种
	LayoutCompact = "20060102150405"      // 紧凑型（日志文件名、ID）
	LayoutDay     = "2006-01-02"          // 只要日期
)

// FormatOrderTime 把订单时间格式化成人能看的样子（固定北京时间）
func FormatOrderTime(t time.Time) string {
	return t.In(time.FixedZone("CST", 8*3600)).Format(LayoutOrder)
}

// ParseOrderTime 解析业务侧传来的时间字符串。
// ★ 用 ParseInLocation：不带时区的字符串按"东八区"解释，而不是 UTC
func ParseOrderTime(s string) (time.Time, error) {
	return time.ParseInLocation(LayoutOrder, s, time.FixedZone("CST", 8*3600))
}

// ============ ④ 单调时钟 ============

func measure(kind string) time.Duration {
	start := time.Now()
	time.Sleep(250 * time.Millisecond)
	switch kind {
	case "correct":
		return time.Since(start)
	case "trap":
		return time.Since(start.Truncate(time.Second)) // ← 把截断过的时间当起点
	}
	return 0
}

// ============ main ============

func main() {
	// ---------- ① 定时任务 ----------
	fmt.Println("① 定时任务骨架：Ticker + ctx 收口 + Stop")
	ctx, cancel := context.WithCancel(context.Background())
	runs := RunPeriodic(ctx, 40*time.Millisecond, 5, func(run int, drift time.Duration) {
		fmt.Printf("   run #%d 已运行 %v\n", run, drift.Round(time.Millisecond))
	})
	cancel()
	fmt.Printf("   返回 %d 次运行（maxRuns=5 到点主动返回）\n", runs)

	// 再看一次"ctx 先取消"的路径
	ctx2, cancel2 := context.WithCancel(context.Background())
	go func() { time.Sleep(60 * time.Millisecond); cancel2() }()
	runs2 := RunPeriodic(ctx2, 40*time.Millisecond, 0, func(int, time.Duration) {})
	fmt.Printf("   ctx 在 60ms 时取消 → 返回 %d 次运行（Ticker 已被 defer Stop）\n", runs2)

	// ---------- ② 热路径分配 ----------
	const N = 200000
	fmt.Printf("\n② 热路径 %d 次：time.After vs 复用 Timer（累计 TotalAlloc）\n", N)
	afterBytes := allocPerLoop("after", N)
	reuseBytes := allocPerLoop("reuse", N)
	fmt.Printf("   time.After 每次新建：累计分配 %.2f MB（每个约 %.0f B）\n",
		float64(afterBytes)/(1<<20), float64(afterBytes)/float64(N))
	fmt.Printf("   复用同一个 Timer ：累计分配 %.2f MB\n", float64(reuseBytes)/(1<<20))

	// ---------- ③ 格式化与解析 ----------
	fmt.Println("\n③ 订单时间戳：格式化与解析")
	fixed := time.Date(2026, 9, 13, 13, 14, 15, 123456789, time.FixedZone("CST", 8*3600))
	fmt.Printf("   原始时刻   %v\n", fixed)
	fmt.Printf("   LayoutOrder   %q → %s\n", LayoutOrder, fixed.Format(LayoutOrder))
	fmt.Printf("   LayoutCompact %q → %s\n", LayoutCompact, fixed.Format(LayoutCompact))
	fmt.Printf("   LayoutDay     %q → %s\n", LayoutDay, fixed.Format(LayoutDay))
	fmt.Printf("   RFC3339           → %s\n", fixed.Format(time.RFC3339))
	fmt.Printf("   RFC3339Nano       → %s\n", fixed.Format(time.RFC3339Nano))

	parsed, err := ParseOrderTime("2026-09-13 13:14:15")
	fmt.Printf("   ParseInLocation(%q) → %v（Unix=%d）\n", LayoutOrder, parsed, parsed.Unix())
	parsedUTC, _ := time.Parse(LayoutOrder, "2026-09-13 13:14:15")
	fmt.Printf("   Parse          (%q) → %v（Unix=%d）← 差 8 小时\n", LayoutOrder, parsedUTC, parsedUTC.Unix())

	_, err = ParseOrderTime("2026/09/13 13:14:15")
	fmt.Printf("   解析错格式 → err=%v\n", err)

	// 写错布局串：不报错，原样吐出字面量
	fmt.Printf("   布局串写成 YYYY-MM-DD HH:mm:ss → %q ← 不报错，就是原样输出\n",
		fixed.Format("YYYY-MM-DD HH:mm:ss"))

	// 两位年的 69 分界
	for _, s := range []string{"68-01-01", "69-01-01", "99-01-01"} {
		t, _ := time.Parse("06-01-02", s)
		fmt.Printf("   两位年 %q → %s\n", s, t.Format("2006-01-02"))
	}

	// AddDate 月末回绕
	jan31 := time.Date(2026, 1, 31, 0, 0, 0, 0, time.UTC)
	fmt.Printf("   2026-01-31 AddDate(0,1,0) → %s（不是 02-28，也不是 03-01）\n",
		jan31.AddDate(0, 1, 0).Format("2006-01-02"))
	fmt.Printf("   2026-01-31 AddDate(0,0,30)→ %s（按「天」加才是 03-02）\n",
		jan31.AddDate(0, 0, 30).Format("2006-01-02"))

	// ---------- ④ 单调时钟 ----------
	fmt.Println("\n④ 单调时钟：同一段 250ms 的睡眠，两种写法")
	correct := measure("correct")
	trap := measure("trap")
	fmt.Printf("   time.Since(start)                = %v\n", correct)
	fmt.Printf("   time.Since(start.Truncate(1s))    = %v ← 凭空多算了 start 的小数秒\n", trap)

	now := time.Now()
	fmt.Printf("   t == t.Round(0)      → %v（== 连单调读一起比）\n", now == now.Round(0))
	fmt.Printf("   t.Equal(t.Round(0))  → %v（Equal 只比时刻）\n", now.Equal(now.Round(0)))

	// Unix 时间戳精度
	fmt.Printf("\n   Unix()=%d UnixMilli()=%d UnixNano()=%d\n",
		fixed.Unix(), fixed.UnixMilli(), fixed.UnixNano())
	fmt.Printf("   time.Unix(秒) 往返 → %v（纳秒被抹掉）\n",
		time.Unix(fixed.Unix(), 0).UTC().Format(time.RFC3339Nano))

	// Duration 的 Round / Truncate
	d := 91*time.Second + 234*time.Millisecond
	fmt.Printf("   Duration %v：Truncate(1s)=%v Round(1s)=%v\n", d, d.Truncate(time.Second), d.Round(time.Second))
}

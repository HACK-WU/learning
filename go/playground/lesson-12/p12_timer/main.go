// p12_timer —— Ticker / Timer 的 Stop、Reset 与「到底还需不需要 Stop」。
package main

import (
	"fmt"
	"runtime"
	"time"
)

func heapMB() float64 {
	runtime.GC()
	runtime.GC()
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	return float64(m.HeapAlloc) / (1 << 20)
}

func main() {
	// ---------------------------------------------------------------- 1
	fmt.Println("1) 文档说 NewTimer 的 channel 是「unbuffered, capacity 0」，那 cap() 是多少？")
	tm := time.NewTimer(time.Hour)
	defer tm.Stop()
	fmt.Printf("   cap(time.NewTimer(time.Hour).C)        = %d\n", cap(tm.C))
	tk := time.NewTicker(time.Hour)
	defer tk.Stop()
	fmt.Printf("   cap(time.NewTicker(time.Hour).C)       = %d\n", cap(tk.C))
	fmt.Printf("   cap(time.After(time.Hour))             = %d\n", cap(time.After(time.Hour)))
	fmt.Println("   源码里两处都是 make(chan Time, 1)；“capacity 0”指的是运行时的同步发送语义，")
	fmt.Println("   不是 cap() 的返回值 —— 这正是“文档与实测各说各话”的典型。")
	fmt.Println()
	_ = time.NewTimer(time.Hour).Stop()

	// ---------------------------------------------------------------- 2
	fmt.Println("2) Ticker 正常走字 + Stop 之后不再有 tick")
	t2 := time.NewTicker(20 * time.Millisecond)
	n := 0
	deadline := time.After(150 * time.Millisecond)
loop:
	for {
		select {
		case <-t2.C:
			n++
		case <-deadline:
			break loop
		}
	}
	t2.Stop()
	fmt.Printf("   150ms / 20ms → 收到 %d 个 tick（预期约 7 个）\n", n)

	// Stop 之后再等一会儿，看还有没有 tick
	extra := 0
	wait := time.After(100 * time.Millisecond)
loop2:
	for {
		select {
		case <-t2.C:
			extra++
		case <-wait:
			break loop2
		}
	}
	fmt.Printf("   Stop() 之后再等 100ms → 又收到 %d 个 tick\n", extra)

	// Stop 不会关 channel
	select {
	case v := <-t2.C:
		fmt.Printf("   从已 Stop 的 Ticker.C 读到 %v（不应该发生）\n", v)
	case <-time.After(60 * time.Millisecond):
		fmt.Println("   从已 Stop 的 Ticker.C 接收：阻塞住了 ← Stop 不关 channel（这是规范行为）")
	}
	fmt.Println()

	// ---------------------------------------------------------------- 3
	fmt.Println("3) Timer.Stop 的返回值与「Stop 之后读 t.C 会怎样」")
	t3 := time.NewTimer(300 * time.Millisecond)
	fmt.Printf("   还没到期就 Stop() → 返回 %v\n", t3.Stop())
	fmt.Printf("   已经 Stop 过再 Stop() → 返回 %v\n", t3.Stop())
	select {
	case v := <-t3.C:
		fmt.Printf("   Stop 返回 true 之后读 t.C，读到 %v（Go 1.23 起不该发生）\n", v)
	case <-time.After(80 * time.Millisecond):
		fmt.Println("   Stop 返回 true 之后读 t.C → 一直阻塞（Go 1.23 起的保证：不会读到陈旧值）")
	}

	t4 := time.NewTimer(60 * time.Millisecond)
	time.Sleep(120 * time.Millisecond) // 让它先到期
	fmt.Printf("   已到期之后再 Stop() → 返回 %v（false = 没拦住）\n", t4.Stop())
	fmt.Printf("   此时 channel 里有没有值：")
	select {
	case v := <-t4.C:
		fmt.Printf("有，%v\n", v.Format("15:04:05.000"))
	default:
		fmt.Println("没有")
	}
	fmt.Println()

	// ---------------------------------------------------------------- 4
	fmt.Println("4) Timer.Reset 的返回值")
	t5 := time.NewTimer(time.Hour)
	fmt.Printf("   活跃状态 Reset(50ms) → 返回 %v（true = 原本还活着）\n", t5.Reset(50*time.Millisecond))
	<-t5.C
	fmt.Printf("   已到期后 Reset(50ms) → 返回 %v（false = 原本已经死了）\n", t5.Reset(50*time.Millisecond))
	<-t5.C
	t5.Stop()
	fmt.Println()

	// ---------------------------------------------------------------- 5
	fmt.Println("5) 慢接收者：Ticker 会「丢 tick」而不是排队")
	t6 := time.NewTicker(5 * time.Millisecond)
	time.Sleep(120 * time.Millisecond) // 故意不接收，让它积压
	got := 0
	drain := time.After(1 * time.Millisecond)
drainLoop:
	for {
		select {
		case <-t6.C:
			got++
		default:
			break drainLoop
		}
	}
	_ = drain
	t6.Stop()
	fmt.Printf("   5ms 的 ticker 放着 120ms 不读，队列里只积压了 %d 个（预期应约 24 个）\n", got)
	fmt.Println("   → 官方原文：ticker will adjust the time interval or drop ticks to make up for slow receivers")
	fmt.Println()

	// ---------------------------------------------------------------- 6
	fmt.Println("6) Ticker.Reset 换周期")
	t7 := time.NewTicker(100 * time.Millisecond)
	t7.Reset(10 * time.Millisecond)
	cnt := 0
	end := time.After(120 * time.Millisecond)
r7:
	for {
		select {
		case <-t7.C:
			cnt++
		case <-end:
			break r7
		}
	}
	t7.Stop()
	fmt.Printf("   Reset 到 10ms 后 120ms 内收到 %d 个 tick（若还是 100ms 只会有 1 个）\n", cnt)
	fmt.Println()

	// ---------------------------------------------------------------- 7
	fmt.Println("7) 不 Stop 的 Ticker/Timer 会不会泄漏？Go 1.23 起 GC 能回收未 Stop 的")
	goroutinesBefore := runtime.NumGoroutine()
	base := heapMB()
	const N = 300000
	for i := 0; i < N; i++ {
		time.NewTicker(time.Hour) // 故意不保存引用、也不 Stop
	}
	afterTicker := heapMB()
	for i := 0; i < N; i++ {
		time.NewTimer(time.Hour)
	}
	afterTimer := heapMB()
	for i := 0; i < N; i++ {
		time.AfterFunc(time.Hour, func() {})
	}
	afterFunc := heapMB()
	fmt.Printf("   基线堆 = %.2f MB\n", base)
	fmt.Printf("   %d 个未 Stop 的 Ticker  之后 = %.2f MB（增量 %.2f MB）\n", N, afterTicker, afterTicker-base)
	fmt.Printf("   %d 个未 Stop 的 Timer   之后 = %.2f MB（增量 %.2f MB）\n", N, afterTimer, afterTimer-base)
	fmt.Printf("   %d 个未 Stop 的 AfterFunc 之后 = %.2f MB（增量 %.2f MB）\n", N, afterFunc, afterFunc-base)
	fmt.Printf("   goroutine 数：%d → %d（定时器不需要一个 goroutine 一个）\n",
		goroutinesBefore, runtime.NumGoroutine())
	fmt.Println("   → 官方原文：as of Go 1.23, the GC can recover unreferenced timers/tickers, even")
	fmt.Println("     if they haven't expired or been stopped. The Stop method is no longer necessary")
	fmt.Println("     to help the garbage collector.  ← 老教材里“必须 Stop 否则泄漏”已经过时")

	// ---------------------------------------------------------------- 8
	fmt.Println()
	fmt.Println("8) AfterFunc 的 Stop")
	fired := false
	t8 := time.AfterFunc(200*time.Millisecond, func() { fired = true })
	fmt.Printf("   200ms 动作，立刻 Stop() → %v\n", t8.Stop())
	time.Sleep(300 * time.Millisecond)
	fmt.Printf("   等 300ms 后 fired = %v（被 Stop 拦住了）\n", fired)
	fmt.Printf("   AfterFunc 返回的 Timer，其 C 字段 = %v（官方：is not used and will be nil）\n", t8.C)
}

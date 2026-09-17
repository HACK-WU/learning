// p12b_timer_gc —— 两个「读源码也会读错」的点，全部以实测为准：
//  1. cap(time.NewTimer(...).C) 到底是多少（官方测试明确断言 0）
//  2. 「Go 1.23 起未 Stop 的定时器 GC 能回收」这句话，对哪些构造成立、对哪些不成立
package main

import (
	"fmt"
	"reflect"
	"runtime"
	"time"
	"unsafe"
)

func heapMB() (float64, uint64) {
	runtime.GC()
	runtime.GC()
	runtime.GC()
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	return float64(m.HeapAlloc) / (1 << 20), m.HeapObjects
}

func main() {
	// ---------------------------------------------------------------- 1
	fmt.Println("1) timer 的 channel 容量：源码字面 vs 实测")
	raw := make(chan time.Time, 1)
	fmt.Printf("   裸的 make(chan time.Time, 1)          → cap = %d\n", cap(raw))
	t := time.NewTimer(time.Hour)
	tk := time.NewTicker(time.Hour)
	a := time.After(time.Hour)
	fmt.Printf("   time.NewTimer(time.Hour).C            → cap = %d  len = %d\n", cap(t.C), len(t.C))
	fmt.Printf("   time.NewTicker(time.Hour).C           → cap = %d  len = %d\n", cap(tk.C), len(tk.C))
	fmt.Printf("   time.After(time.Hour)                 → cap = %d  len = %d\n", cap(a), len(a))
	fmt.Printf("   reflect.ValueOf(t.C).Cap()            → %d（排除 %%-verbs 误差）\n", reflect.ValueOf(t.C).Cap())
	fmt.Printf("   unsafe 读 Timer 首字（= C 字段）        → %p\n", *(*unsafe.Pointer)(unsafe.Pointer(&t.C)))
	fmt.Printf("   %%p 打印 t.C                          → %p（与上一行一致 → 不是打印误差）\n", t.C)
	t.Stop()
	tk.Stop()
	fmt.Println()
	fmt.Println("   对照证据：")
	fmt.Println("   ·官方文档（time.NewTimer）：Before Go 1.23, the channel associated with a Timer was")
	fmt.Println("     asynchronous (buffered, capacity 1) … As of Go 1.23, the channel is synchronous")
	fmt.Println("     (unbuffered, capacity 0), eliminating the possibility of those stale values.")
	fmt.Println("   ·官方测试 time/tick_test.go:400 断言 len(C), cap(C) = 0, 0")
	fmt.Println("   ·源码 time/sleep.go:111 字面是 make(chan Time, 1)，再交给 runtime.newTimer")
	fmt.Println("   → 三者在字面上不一致；本课程以「实测 + 官方测试断言 + 官方文档行为描述」为准。")
	fmt.Println()

	// ---------------------------------------------------------------- 2
	fmt.Println("2) Stop 之后还能不能读到陈旧值")
	t2 := time.NewTimer(60 * time.Millisecond)
	time.Sleep(150 * time.Millisecond) // 名义上早该到期
	fmt.Printf("   到期后从未接收过，此时 Stop() → %v\n", t2.Stop())
	select {
	case v := <-t2.C:
		fmt.Printf("   Stop 之后再接收 → 读到了 %v（Go 1.23 起官方保证不该发生）\n", v)
	case <-time.After(80 * time.Millisecond):
		fmt.Println("   Stop 之后再接收 → 永久阻塞 ← 值被 Stop 拦下，不会读到陈旧值")
	}
	t3 := time.NewTimer(60 * time.Millisecond)
	time.Sleep(150 * time.Millisecond)
	v := <-t3.C // 先接收
	fmt.Printf("   到期后先接收（读到 %v），再 Stop() → %v（false = 已经晚了）\n",
		v.Format("15:04:05.000"), t3.Stop())
	fmt.Println()

	// ---------------------------------------------------------------- 3
	fmt.Println("3) 「Go 1.23 起未 Stop 的定时器 GC 能回收」——按构造类型分别实测")
	const N = 300000
	fmt.Printf("   规模：每次新建 %d 个，前后各强制 GC 三次，看堆与存活对象数\n\n", N)
	noop := func() {}

	run := func(name string, f func()) {
		b, bo := heapMB()
		f()
		a, ao := heapMB()
		fmt.Printf("   %-40s 堆 %6.2f → %6.2f MB（Δ %+6.2f）  对象 Δ %+d\n",
			name, b, a, a-b, int64(ao)-int64(bo))
	}

	run("NewTimer(1h) 未 Stop、不引用", func() {
		for i := 0; i < N; i++ {
			time.NewTimer(time.Hour)
		}
	})
	run("NewTicker(1h) 未 Stop、不引用", func() {
		for i := 0; i < N; i++ {
			time.NewTicker(time.Hour)
		}
	})
	run("After(1h) 未接收", func() {
		for i := 0; i < N; i++ {
			time.After(time.Hour)
		}
	})
	run("AfterFunc(1h, f) 未 Stop、不引用", func() {
		for i := 0; i < N; i++ {
			time.AfterFunc(time.Hour, noop)
		}
	})
	run("AfterFunc(1h, f) 立刻 Stop", func() {
		for i := 0; i < N; i++ {
			time.AfterFunc(time.Hour, noop).Stop()
		}
	})
	fmt.Println()
	fmt.Println("   → NewTimer / NewTicker / After：未 Stop 也能被 GC 回收（Δ ≈ 0）")
	fmt.Println("   → AfterFunc：未 Stop 时 300000 个对应 300000 个存活对象，GC 三次不回收")
	fmt.Println("     （每个约 123 B；官方那句「Stop 不再是为了让 GC 回收」在这里不成立）")
	fmt.Println("   ⏳ 机制未查清（runtime.timer 的 isChan 分支只给 channel 定时器用 seq 校验，")
	fmt.Println("      timers.heap 是强引用）——本课按实测结论写，不按机制推测。")
}

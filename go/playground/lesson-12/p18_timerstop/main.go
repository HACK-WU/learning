// p18_timerstop：把 Timer.Stop() 的返回值语义测准。
//
// 为什么单独建一个探针：课 12 初稿里写了「Stop() 返回 false = 已经响过 或 已停过（两种含义）」，
// 但那句话抄自老版文档。Go 1.23 起 NewTimer 的 channel 从「有缓冲(容量1)」改成「同步(容量0)」，
// 文档也补了一句：「if the program has not received from t.C already and the timer is running,
// Stop is guaranteed to return true」——这会让「已到期但值没被接收」这一格的结果**变掉**。
// 实测一下到底怎么变。
package main

import (
	"fmt"
	"time"
)

func stopCall(label string, t *time.Timer) {
	fmt.Printf("   %-48s → %v\n", label, t.Stop())
}

func main() {
	noop := func() {}

	fmt.Println("A) chan-based timer（NewTimer）：5 种情形下 Stop() 返回什么")
	fmt.Println("   ----------------------------------------------")

	// A1/A2 立刻 Stop，再 Stop 一次
	t1 := time.NewTimer(time.Hour)
	stopCall("① 还没到期就 Stop()", t1)
	stopCall("② 已经 Stop 过再 Stop()", t1)

	// A3 已到期，但值从未被接收
	t3 := time.NewTimer(50 * time.Millisecond)
	time.Sleep(120 * time.Millisecond)
	stopCall("③ 已到期、值从未被接收 → Stop()", t3)
	select {
	case <-t3.C:
		fmt.Println("      ↳ Stop() 之后从 t.C 读到了值（不该发生）")
	default:
		fmt.Println("      ↳ Stop() 之后从 t.C 读不到值")
	}

	// A4 已到期，并且值已经被接收
	t4 := time.NewTimer(50 * time.Millisecond)
	<-t4.C
	stopCall("④ 已到期、值已被接收 → Stop()", t4)

	// A5 到期后 Reset 再 Stop
	t5 := time.NewTimer(50 * time.Millisecond)
	time.Sleep(120 * time.Millisecond)
	fmt.Printf("   %-48s → %v\n", "⑤ 已到期、值未接收，Reset(1h)", t5.Reset(time.Hour))
	stopCall("⑥ Reset 之后再 Stop()", t5)

	fmt.Println()
	fmt.Println("B) func-based timer（AfterFunc）：3 种情形")
	fmt.Println("   ----------------------------------------------")

	t6 := time.AfterFunc(time.Hour, noop)
	stopCall("① 还没到期就 Stop()", t6)

	fired := 0
	done := make(chan struct{})
	t7 := time.AfterFunc(50*time.Millisecond, func() { fired++; close(done) })
	select {
	case <-done:
	case <-time.After(300 * time.Millisecond):
	}
	stopCall(fmt.Sprintf("② 已到期、回调已跑（fired=%d）→ Stop()", fired), t7)

	fired2 := 0
	t8 := time.AfterFunc(80*time.Millisecond, func() { fired2++ })
	ok := t8.Stop()
	time.Sleep(200 * time.Millisecond)
	fmt.Printf("   %-48s → %v（回调被拦住了吗：%v）\n", "③ 立刻 Stop() 拦回调", ok, fired2 == 0)

	fmt.Println()
	fmt.Println("C) AfterFunc 的 Timer.C 与 chan-based 的差别")
	t9 := time.AfterFunc(time.Hour, noop)
	fmt.Printf("   AfterFunc(...).C == nil ？%v\n", t9.C == nil)
	t10 := time.NewTimer(time.Hour)
	fmt.Printf("   NewTimer(...).C  == nil ？%v\n", t10.C == nil)
	t9.Stop()
	t10.Stop()

	fmt.Println()
	fmt.Println("D) 结论（只写实测到的）")
	fmt.Println("   chan-based（NewTimer）：")
	fmt.Println("     · 值从未被接收 → Stop() 返回 true（**已到期也不例外**，这是 Go 1.23 起的行为）")
	fmt.Println("     · 已经被 Stop 过 / 值已被接收 → Stop() 返回 false")
	fmt.Println("   func-based（AfterFunc）：")
	fmt.Println("     · 回调已经跑过 → Stop() 返回 false（这一格才是文档里说的「没拦住」）")
}

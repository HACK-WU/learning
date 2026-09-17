// p11_monotonic —— time.Time 里的「单调时钟读」到底是啥，以及哪些操作会把它弄丢。
package main

import (
	"encoding/json"
	"fmt"
	"time"
)

func main() {
	fmt.Println("1) time.Now() 身上带着单调读，t.String() 会把它显示出来")
	t := time.Now()
	fmt.Printf("   time.Now()        = %v\n", t)
	fmt.Printf("   t.Round(0)        = %v\n", t.Round(0))
	fmt.Printf("   t == t.Round(0)   → %v   ← == 连单调读一起比\n", t == t.Round(0))
	fmt.Printf("   t.Equal(t.Round(0)) → %v ← Equal 只比“时刻”\n", t.Equal(t.Round(0)))
	fmt.Println()

	fmt.Println("2) 拿 time.Time 当 map key：几乎永远取不回来")
	m := map[time.Time]string{}
	m[t] = "我是 t"
	_, ok1 := m[t]
	_, ok2 := m[time.Now()]
	_, ok3 := m[t.Round(0)]
	fmt.Printf("   用同一个 t 取        → ok=%v\n", ok1)
	fmt.Printf("   用 time.Now() 重取    → ok=%v\n", ok2)
	fmt.Printf("   用 t.Round(0) 取      → ok=%v\n", ok3)
	fmt.Println("   （所以官方给的标准做法是：当 key 前先 t = t.Round(0)，并用 t.Equal 比较）")
	fmt.Println()

	fmt.Println("3) 哪些操作会把单调读丢掉（官方包文档列过）")
	ops := []struct {
		name string
		f    func(time.Time) time.Time
	}{
		{"Round(0)", func(x time.Time) time.Time { return x.Round(0) }},
		{"Round(time.Second)", func(x time.Time) time.Time { return x.Round(time.Second) }},
		{"Truncate(time.Second)", func(x time.Time) time.Time { return x.Truncate(time.Second) }},
		{"AddDate(0,0,0)", func(x time.Time) time.Time { return x.AddDate(0, 0, 0) }},
		{"UTC()", func(x time.Time) time.Time { return x.UTC() }},
		{"Local()", func(x time.Time) time.Time { return x.Local() }},
		{"In(time.UTC)", func(x time.Time) time.Time { return x.In(time.UTC) }},
		{"Add(time.Hour)", func(x time.Time) time.Time { return x.Add(time.Hour) }},
		{"JSON 往返", func(x time.Time) time.Time {
			b, _ := json.Marshal(x)
			var y time.Time
			_ = json.Unmarshal(b, &y)
			return y
		}},
	}
	for _, op := range ops {
		y := op.f(t)
		hasMono := y.String() != y.Round(0).String()
		fmt.Printf("   %-22s → 还有单调读吗：%v\n", op.name, hasMono)
	}
	fmt.Println()

	fmt.Println("4) 丢了单调读的后果之一：精度被“截断”到布局粒度")
	// 取一个刻意落在秒中间的时刻
	t2 := time.Now()
	sec := t2.Truncate(time.Second)
	fmt.Printf("   原始       = %v\n", t2.Format("15:04:05.000000000"))
	fmt.Printf("   截断到秒   = %v\n", sec.Format("15:04:05.000000000"))
	fmt.Printf("   t2.Sub(截断值) = %v（正的，等于小数秒）\n", t2.Sub(sec))
	fmt.Printf("   截断值.Sub(t2) = %v（负的，同一个差值）\n", sec.Sub(t2))
	fmt.Println()

	fmt.Println("5) 后果之二：把「截断过的时间」当计时起点，会凭空多算最多 1 秒")
	// 真实计时：睡 250ms
	start := time.Now()
	time.Sleep(250 * time.Millisecond)
	real := time.Since(start)
	wrong := time.Since(start.Truncate(time.Second))
	fmt.Printf("   正常计时 time.Since(start)                 = %v\n", real.Round(time.Millisecond))
	fmt.Printf("   踩坑计时 time.Since(start.Truncate(1s))     = %v ← 多算了 start 的小数秒\n",
		wrong.Round(time.Millisecond))
	fmt.Printf("   多算的部分 = %v（本该为 0）\n", (wrong - real).Round(time.Millisecond))
	fmt.Println()

	fmt.Println("6) time.Since 与 time.Now().Sub 等价，但内部走的是快车道")
	fmt.Printf("   time.Since(start)    = %v\n", time.Since(start).Round(time.Microsecond))
	fmt.Printf("   time.Now().Sub(start)= %v\n", time.Now().Sub(start).Round(time.Microsecond))
	fmt.Println("   （源码里 Since 在 t 带单调读时直接调 subMono(runtimeNano()-startNano, t.ext)，")
	fmt.Println("     省掉一次 Now() 的墙上时钟构造）")
	fmt.Println()

	fmt.Println("7) 同一个时刻、不同 Location：== 不等，Equal 相等")
	utc := t.Round(0).UTC()
	loc := utc.In(time.FixedZone("CST", 8*3600))
	fmt.Printf("   t（本地）      = %v\n", t.Round(0).Format("2006-01-02 15:04:05 -0700 MST"))
	fmt.Printf("   转成固定 +8 区  = %v\n", loc.Format("2006-01-02 15:04:05 -0700 MST"))
	fmt.Printf("   utc == loc     → %v\n", utc == loc)
	fmt.Printf("   utc.Equal(loc) → %v\n", utc.Equal(loc))
	fmt.Printf("   utc.Sub(loc)   → %v\n", utc.Sub(loc))
}

// p14_layout —— 时间格式化与解析：那个「魔数布局串」到底怎么来的、坑在哪。
package main

import (
	"fmt"
	"time"
)

func main() {
	// ---------------------------------------------------------------- 1
	fmt.Println("1) 参考时间到底长什么样")
	fmt.Printf("   time.Layout 常量        = %q\n", time.Layout)
	fmt.Printf("   官方文档里的参考时间     = %q（= UnixDate）\n", time.UnixDate)
	fmt.Printf("   ANSIC                   = %q\n", time.ANSIC)
	fmt.Printf("   RFC3339                 = %q\n", time.RFC3339)
	fmt.Printf("   Kitchen                 = %q\n", time.Kitchen)
	fmt.Printf("   DateTime                = %q\n", time.DateTime)
	fmt.Println()

	// 固定一个时刻，保证输出可复现
	loc := time.FixedZone("CST", 8*3600)
	t := time.Date(2026, 9, 13, 13, 14, 15, 123456789, loc)
	fmt.Printf("2) 用同一个时刻 %s 试各种布局\n", t.Format("2006-01-02 15:04:05.000 -0700"))
	layouts := []struct{ name, layout string }{
		{"DateTime", "2006-01-02 15:04:05"},
		{"带毫秒", "2006-01-02 15:04:05.000"},
		{"带时区偏移", "2006-01-02 15:04:05 -0700"},
		{"带时区名", "2006-01-02 15:04:05 MST"},
		{"RFC3339", time.RFC3339},
		{"RFC3339Nano", time.RFC3339Nano},
		{"UnixDate", time.UnixDate},
		{"ANSIC", time.ANSIC},
		{"Kitchen", time.Kitchen},
		{"只要年月", "2006-01"},
		{"月/日 12 小时制", "01/02 03:04:05PM"},
		{"两位年", "06-01-02"},
		{"一年中的第几天", "2006-002"},
		{"星期几", "Monday"},
		{"带小数秒（去尾零）", "15:04:05.999"},
	}
	for _, l := range layouts {
		fmt.Printf("   %-20s %-28q → %s\n", l.name, l.layout, t.Format(l.layout))
	}
	fmt.Println()

	// ---------------------------------------------------------------- 3
	fmt.Println("3) 布局串写错会怎样：Format 不报错，只是原样吐出你的字面量")
	bad := []string{
		"2006-01-02 15:04:05", // 对
		"YYYY-MM-DD HH:mm:ss", // 错：PHP/Java 风格
		"2006-1-2",            // 错：月份/日期没补零
		"2006-01-02 3:04:05",  // 错：24 小时写成 3
		"2006/01/02",          // 对：只是分隔符不同
	}
	for _, b := range bad {
		fmt.Printf("   %-24q → %q\n", b, t.Format(b))
	}
	fmt.Println()

	// ---------------------------------------------------------------- 4
	fmt.Println("4) Parse 会挑错（原文照抄）")
	parses := []struct {
		layout, value string
	}{
		{"2006-01-02 15:04:05", "2026-09-13 13:14:15"},
		{"2006-01-02 15:04:05", "2026/09/13 13:14:15"},
		{"2006-01-02", "2026-13-01"},
		{"2006-01-02 15:04:05", "2026-09-13"},
	}
	for _, p := range parses {
		got, err := time.Parse(p.layout, p.value)
		if err != nil {
			fmt.Printf("   Parse(%-22q, %-22q) → err = %v\n", p.layout, p.value, err)
			continue
		}
		fmt.Printf("   Parse(%-22q, %-22q) → %s\n", p.layout, p.value, got.Format("2006-01-02 15:04:05 -0700 MST"))
	}
	fmt.Println()

	// ---------------------------------------------------------------- 5
	fmt.Println("5) 不带时区的字符串：Parse 当成 UTC，ParseInLocation 按给定位置")
	layouts2 := []struct {
		name string
		f    func() (time.Time, error)
	}{
		{"Parse", func() (time.Time, error) { return time.Parse("2006-01-02 15:04:05", "2026-09-13 13:14:15") }},
		{"ParseInLocation(time.Local)", func() (time.Time, error) {
			return time.ParseInLocation("2006-01-02 15:04:05", "2026-09-13 13:14:15", time.Local)
		}},
		{"ParseInLocation(Asia/Shanghai)", func() (time.Time, error) {
			l, err := time.LoadLocation("Asia/Shanghai")
			if err != nil {
				return time.Time{}, err
			}
			return time.ParseInLocation("2006-01-02 15:04:05", "2026-09-13 13:14:15", l)
		}},
	}
	for _, l := range layouts2 {
		got, err := l.f()
		if err != nil {
			fmt.Printf("   %-30s → err = %v\n", l.name, err)
			continue
		}
		fmt.Printf("   %-30s → %s  (Unix=%d)\n", l.name,
			got.Format("2006-01-02 15:04:05 MST"), got.Unix())
	}
	fmt.Println()

	// ---------------------------------------------------------------- 6
	fmt.Println("6) 两位年 '06' 的 69 分界（官方原文：>=69 当 19xx，<69 当 20xx）")
	for _, v := range []string{"68-01-01", "69-01-01", "70-01-01", "00-01-01", "99-01-01"} {
		got, err := time.Parse("06-01-02", v)
		if err != nil {
			fmt.Printf("   %-10q → err = %v\n", v, err)
			continue
		}
		fmt.Printf("   %-10q → %s\n", v, got.Format("2006-01-02"))
	}
	fmt.Println()

	// ---------------------------------------------------------------- 7
	fmt.Println("7) 时区数据库")
	for _, name := range []string{"Asia/Shanghai", "America/New_York", "UTC", "不存在的时区", "Local"} {
		l, err := time.LoadLocation(name)
		if err != nil {
			fmt.Printf("   LoadLocation(%-20q) → err = %v\n", name, err)
			continue
		}
		fmt.Printf("   LoadLocation(%-20q) → %s\n", name, t.In(l).Format("2006-01-02 15:04:05 MST -0700"))
	}
	fmt.Println()

	// ---------------------------------------------------------------- 8
	fmt.Println("8) Unix 时间戳：秒 / 毫秒 / 纳秒")
	now := time.Date(2026, 9, 13, 13, 14, 15, 123456789, time.UTC)
	fmt.Printf("   Unix()      = %d\n", now.Unix())
	fmt.Printf("   UnixMilli() = %d\n", now.UnixMilli())
	fmt.Printf("   UnixMicro() = %d\n", now.UnixMicro())
	fmt.Printf("   UnixNano()  = %d\n", now.UnixNano())
	back := time.Unix(now.Unix(), 0).UTC()
	fmt.Printf("   time.Unix(秒) 往返丢精度 → %s（纳秒被抹掉）\n",
		back.Format("2006-01-02 15:04:05.000000000"))
	back2 := time.UnixMilli(now.UnixMilli()).UTC()
	fmt.Printf("   time.UnixMilli 往返     → %s（毫秒精度）\n",
		back2.Format("2006-01-02 15:04:05.000000000"))
	// 2262 年溢出边界
	far := time.Date(2262, 4, 11, 23, 47, 16, 0, time.UTC)
	fmt.Printf("   2262-04-11 23:47:16 的 UnixNano = %d\n", far.UnixNano())
	over := time.Date(2263, 1, 1, 0, 0, 0, 0, time.UTC)
	fmt.Printf("   2263-01-01 的 UnixNano          = %d ← int64 纳秒溢出成负数\n", over.UnixNano())
	fmt.Println()

	// ---------------------------------------------------------------- 9
	fmt.Println("9) AddDate 的月末回绕（不是“加 30 天”）")
	base := time.Date(2026, 1, 31, 12, 0, 0, 0, time.UTC)
	fmt.Printf("   2026-01-31 AddDate(0,1,0) → %s\n", base.AddDate(0, 1, 0).Format("2006-01-02"))
	fmt.Printf("   2026-01-31 AddDate(0,3,0) → %s\n", base.AddDate(0, 3, 0).Format("2006-01-02"))
	fmt.Printf("   2026-08-31 AddDate(0,1,0) → %s\n",
		time.Date(2026, 8, 31, 12, 0, 0, 0, time.UTC).AddDate(0, 1, 0).Format("2006-01-02"))
	fmt.Printf("   2026-03-31 AddDate(0,-1,0) → %s\n",
		time.Date(2026, 3, 31, 12, 0, 0, 0, time.UTC).AddDate(0, -1, 0).Format("2006-01-02"))
	fmt.Println()

	// ---------------------------------------------------------------- 10
	fmt.Println("10) 格式化 Duration：Round 与 Truncate 的差别")
	d := 90*time.Second + 1234*time.Millisecond
	fmt.Printf("   d            = %v\n", d)
	fmt.Printf("   Truncate(1s) = %v（向下截）\n", d.Truncate(time.Second))
	fmt.Printf("   Round(1s)    = %v（四舍五入）\n", d.Round(time.Second))
	fmt.Printf("   String()     = %v\n", d.String())
	fmt.Printf("   手写 mm:ss   = %02d:%02d\n", int(d.Minutes()), int(d.Seconds())%60)
}

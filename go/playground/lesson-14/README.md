# 课 14 实操目录：性能与诊断

> 对应课时：[lesson-14-性能与诊断.md](../../stages/5-工程化与生产落地/lessons/lesson-14-性能与诊断.md)
> 本机基线：`go1.27.1 darwin/arm64` ｜ 代码只使用 Go 标准库

## 这份目录验证什么

- `BenchmarkXxx` + `b.N`：比较同一行为的两种实现，并用 `-benchmem` 查看每次操作的分配。
- `runtime/pprof`：生成 CPU、heap、goroutine、block 和 `goroutineleak` 五类 profile，再用 `go tool pprof -top` 查看热点。
- `go build -gcflags=-m=2`：查看编译器的逃逸分析提示。
- `runtime.GC`、预分配容量和 `strings.Builder`：把“减少分配”的想法放进可观察的样例。

## 复跑

```bash
cd go/playground/lesson-14
bash regen.sh > ALL_OUTPUT.txt 2>&1
```

脚本用 `mktemp` 建立临时 profile 目录，并在结束时删除；仓库只保留源码和文本输出，不把机器相关的二进制 profile 当作课程正文。benchmark 的 ns/op、分配量和 pprof 的采样数量会随机器负载变化；看函数热点、方向和退出码，不要把一次运行的微小数字当成规格承诺。

## 目录说明

```text
lesson-14/
├── go.mod
├── hotpath/
│   ├── concat.go
│   └── concat_test.go
├── cmd/profiledemo/
│   └── main.go
├── ALL_OUTPUT.txt
└── regen.sh
```

本例没有引入第三方依赖，因此不安装 `benchstat`；正文会说明它在多次 benchmark A/B 对比中的位置，并链接官方工具方向。

# 课 13 实操目录：模块、测试与规范

> 对应课时：[lesson-13-模块、测试与规范.md](../../stages/5-工程化与生产落地/lessons/lesson-13-模块、测试与规范.md)
> 本机基线：`go1.27.1 darwin/arm64` ｜ 代码只使用 Go 标准库

## 这份目录验证什么

- `go.mod` 声明模块路径与 Go 版本；本例没有第三方依赖，所以不会生成 `go.sum`。
- `orders/order_test.go` 用表驱动测试覆盖 4 组业务校验与 3 组 HTTP 行为。
- `httptest` 在进程内构造请求和响应，不需要占用端口，也不依赖外部服务。
- `go test -race`、`gofmt -l .`、`go vet ./...`、`go build ./...` 一起组成“能跑、能查、能交付”的最小门禁。

## 复跑

```bash
cd go/playground/lesson-13
bash regen.sh > ALL_OUTPUT.txt 2>&1
```

`ALL_OUTPUT.txt` 是本轮实际运行结果的归档。耗时会随机器负载变化；包名、测试名和退出码应保持一致。

## 目录说明

```text
lesson-13/
├── go.mod
├── orders/
│   ├── order.go
│   └── order_test.go
└── cmd/demo/
    └── main.go
```

这里没有把第三方依赖强行塞进示例：课 13 需要理解 `require`、`go.sum`、`vendor` 和 `go.work`，正文中的 `go.mod` 片段会单独解释这些文件的职责。

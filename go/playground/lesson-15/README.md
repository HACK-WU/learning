# 课 15 实操：从源码到可观测、可退出的交付物

> 对应课程：[lesson-15-构建部署与选型决策.md](../../stages/5-工程化与生产落地/lessons/lesson-15-构建部署与选型决策.md)
> 本机基线：`go1.27.1 darwin/arm64`

## 这份目录验证什么

- `-ldflags -X` 把版本、提交号、构建时间注入二进制。
- `CGO_ENABLED=0 GOOS=linux GOARCH=amd64` 产出可放入精简 Linux 镜像的静态 ELF。
- `log/slog` 输出 JSON 日志；`/healthz` 与 `/readyz` 分别表达存活和就绪。
- 公共服务与管理服务分开监听：pprof 只在管理端口可见。
- 收到 `SIGTERM` 后调用 `http.Server.Shutdown`，在途 `/slow` 请求仍返回 200。
- `Dockerfile` 用多阶段构建把编译环境留在 builder stage，运行时只复制二进制。

## 复跑

```bash
cd go/playground/lesson-15
bash regen.sh > ALL_OUTPUT.txt 2>&1
```

脚本使用临时目录保存二进制；Docker 守护进程可用时还会真实构建并运行 scratch 镜像，完成后删除本轮生成的临时镜像。若本机 Docker 未启动，脚本会明确记录跳过原因，但本地 Go 构建、测试和优雅退出演示仍会执行。

端口绑定到 `127.0.0.1:0`，由系统分配临时端口，避免占用固定端口；输出中的端口、时间、镜像 ID 等机器相关字段不作为课程断言。

## 目录说明

```text
lesson-15/
├── go.mod
├── Dockerfile
├── .dockerignore
├── internal/app/
│   ├── app.go
│   └── app_test.go
├── cmd/productiondemo/main.go
├── ALL_OUTPUT.txt
└── regen.sh
```

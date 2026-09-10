# Docker Docs 网页索引

> 起始 URL：https://docs.docker.com/
> 生成日期：2026-09-10 · 范围（scope）：教程/引擎/构建/Compose/Docker Hub/参考手册 · 条目数：309 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 采集自官方 `[llms-full.txt](https://docs.docker.com/llms-full.txt)`（站点有 llms.txt，其完整页清单 1433 条）；按课程口径裁剪：保留容器与镜像、Dockerfile/构建、存储与网络、Compose、Docker Hub、CLI/文件格式参考；**排除** `ai/*`（Sandbox/MCP/Gordon/Model Runner）、`dhi/*`、`desktop/*`、`enterprise/*`、`scout/*`、`extensions/*`、`offload/*`、`build-cloud/*`、`accounts/*`、`subscription-billing/*` 及各分区 `release-notes`

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 时效提醒

Docker 官方文档更新频繁（Engine 大版本约每季度一次，CLI/Compose 更频繁）。
**版本号、默认值、新特性以官网当页为准**——本索引只解决"去哪一页"，不保证页面内容未变。
命令行参数细节本机可直接 `docker <命令> --help` 交叉验证，比 fetch 更快。

## 关联索引

- 事实核查闸门：见 `topic-teach` SKILL.md「事实核查闸门」——索引只解决"去哪一页"，不解决"内容是否过时"
- 本地速查：命令类细节优先 `docker <cmd> --help` / `docker inspect`，比 fetch 文档快
- 版本基线：课程以 Docker Engine **29.x** 为准（核查于 2026-09），Compose 一律 V2 写法 `docker compose`

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 讲清 Docker 是什么、架构长什么样 | [Docker 平台总览](https://docs.docker.com/get-started/docker-overview/) | get-started |
| 讲容器 / 镜像 / 仓库 / Compose 的概念 | [Docker 概念（the-basics）](https://docs.docker.com/get-started/docker-concepts/the-basics/) | get-started |
| 查 Dockerfile 每条指令的写法 | [Dockerfile 参考](https://docs.docker.com/reference/dockerfile/) | reference |
| 查 `docker run` 全部参数 | [docker container run](https://docs.docker.com/reference/cli/docker/container/run/) | cli |
| 讲分层、构建缓存为什么会失效 | [构建缓存失效](https://docs.docker.com/build/cache/invalidation/) | build |
| 讲多阶段构建怎么瘦身 | [多阶段构建](https://docs.docker.com/build/building/multi-stage/) | build |
| 对比三种挂载方式（volume/bind/tmpfs） | [存储总览](https://docs.docker.com/engine/storage/) | engine |
| 讲 bridge 网络与端口映射 | [bridge 网络驱动](https://docs.docker.com/engine/network/drivers/bridge/) | engine |
| 查 compose 文件 services 段全部字段 | [Compose file · services](https://docs.docker.com/reference/compose-file/services/) | compose-file |
| 讲容器为什么不算强隔离、怎么加固 | [Docker 安全（引擎）](https://docs.docker.com/engine/security/) | engine |
| 讲 rootless 与 userns-remap | [Rootless 模式](https://docs.docker.com/engine/security/rootless/) | engine |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | [topics/get-started.md](./topics/get-started.md) | 18 | 平台总览、Docker 概念页（容器/镜像/仓库/Compose）、入门教程 |
| engine | [topics/engine.md](./topics/engine.md) | 87 | 容器运行、存储与卷、网络、日志、安全、守护进程、资源治理、Swarm |
| build | [topics/build.md](./topics/build.md) | 58 | Dockerfile 编写、BuildKit、多阶段、构建缓存、制品与证明、Bake |
| compose | [topics/compose.md](./topics/compose.md) | 30 | Compose 介绍、安装、how-tos（网络/环境变量/启动顺序/生产） |
| docker-hub | [topics/docker-hub.md](./topics/docker-hub.md) | 32 | 仓库增删查、镜像与标签、自动构建、拉取限额、可信内容 |
| cli | [topics/cli.md](./topics/cli.md) | 40 | docker / compose 子命令参考与 CLI 通用能力（格式化/过滤/补全） |
| compose-file | [topics/compose-file.md](./topics/compose-file.md) | 19 | compose 文件各顶层段与字段参考 |
| reference | [topics/reference.md](./topics/reference.md) | 18 | Dockerfile 参考、Engine API、build-checks、术语表、dockerd |
| guides | [topics/guides.md](./topics/guides.md) | 7 | 语言/框架容器化指南与动手 Lab（速览跳过，仅登记） |

## 课程映射（15 课 → 主参考分区）

| 课 | 主题 | 主查分区 |
|----|------|----------|
| 1 | 为什么需要 Docker | get-started |
| 2 | 跑起来第一个容器 | get-started / cli |
| 3 | 镜像的里子：分层与仓库 | get-started / engine / docker-hub |
| 4 | Dockerfile 入门 | build / reference |
| 5 | 启动命令与配置注入 | reference / build |
| 6 | 多阶段构建与镜像瘦身 | build |
| 7 | 数据持久化 | engine |
| 8 | 容器网络 | engine |
| 9 | Compose 编排多容器 | compose / compose-file |
| 10 | 资源限制与进程管理 | engine / cli |
| 11 | 日志与可观测性 | engine |
| 12 | 容器安全边界 | engine / build |
| 13 | CI-CD 与交付流水线 | build / docker-hub |
| 14 | Docker 在容器生态中的位置 | get-started / engine |
| 15 | 决策清单与学习地图 | 全部 |

# 网页索引登记表（Python 分布式应用开发课程）

> 涉及下列站点的问题，先查对应条目所在的分区/路由表，再 web_fetch 取正文
>
> 本目录归 **distributed-python 课程** 使用，随课程走（不登记到仓库根 `.web-index/INDEX.md`）

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 | 索引位置 |
|------|------|----------|------|------|----------|----------|
| gRPC Docs | grpc | https://grpc.io/docs/ | `/docs/languages/python/` + `/docs/guides/` + `/docs/what-is-grpc/` + `/docs/protoc-installation/` | 30 | 2026-11-02 | [grpc/index.md](./grpc/index.md) |

## 只登记不建站级索引的站点

> 这些站只需要少数几个固定页面，建整站索引不划算（成本闸门）。URL 已当场核实，直接引用。

| 站点 | 只用到哪几页 | 用途 |
|------|-------------|------|
| Python 3 官方文档 | `/3/library/asyncio.html`、`/3/library/concurrent.futures.html`、`/3/library/threading.html`、`/3/library/socket.html`、`/3/library/logging.html` | 并发模型边界、网络编程、日志基础 |
| Redis 官方文档 | `/docs/latest/develop/use/patterns/distributed-locks/`、`/docs/latest/commands/set/` | 分布式锁的正确写法与 `SET NX PX` 语义 |
| RFC Editor | `/rfc/rfc9110.html`（HTTP 语义：幂等方法）、`/rfc/rfc7231.html` | 幂等性的规范出处 |

## 版本基线

| 组件 | 课程基线版本 | 索引 URL 版本段 | 说明 |
|------|--------------|-----------------|------|
| Python | 3.12（本机实测 3.12.3） | `/3/`（滚动指向当前稳定版） | 代码只用 3.10+ 语法，覆盖当前受支持版本 |
| grpcio / grpcio-tools | 两者的版本号必须一致 | 文档站不分版本（滚动更新） | 版本错配是新手最常见故障之一 |
| redis-py | 跟随 `redis` 包最新稳定版 | 文档站不分版本 | 仅在锁与幂等两课使用 |

> gRPC 文档站是滚动更新的，不区分版本。课程里凡是与版本强相关的结论（如重试默认开启），正文会单独标注 `核查于 YYYY-MM`。

## 使用约定

1. 需要官方文档出处时，先查对应站的「我要…」列定位页面
2. 定位后用 web_fetch 打开该 URL 取细节，**不要把正文抄进索引**
3. 索引是快照，链接大面积失效时整站重跑重建

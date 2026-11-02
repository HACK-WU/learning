# gRPC 网页索引

> 起始 URL：https://grpc.io/docs/
> 生成日期：2026-11-02 · 范围（scope）：`/docs/languages/python/` + `/docs/guides/` + `/docs/what-is-grpc/` + `/docs/protoc-installation/` · 条目数：30 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 从零写第一个 Python gRPC 服务端与客户端 | [Python Quick start](https://grpc.io/docs/languages/python/quickstart/) | python |
| 查 Python 里四种 RPC（一元 / 服务端流 / 客户端流 / 双向流）怎么写 | [Python Basics tutorial](https://grpc.io/docs/languages/python/basics/) | python |
| 用 protoc 生成 `_pb2.py` / `_pb2_grpc.py` 的命令与参数 | [Python Basics · Generating client and server code](https://grpc.io/docs/languages/python/basics/#generating-client-and-server-code) | python |
| 搞清 deadline（截止时间）如何跨服务传播 | [Deadlines](https://grpc.io/docs/guides/deadlines/) | guides |
| 配客户端自动重试（retryPolicy / maxAttempts / 退避） | [Retry](https://grpc.io/docs/guides/retry/) | guides |
| 判断哪些 status code 该重试、哪些不该 | [Status Codes](https://grpc.io/docs/guides/status-codes/) | guides |
| 请求取消与超时后服务端怎么感知 | [Cancellation](https://grpc.io/docs/guides/cancellation/) | guides |

## 分区索引

| 分区 | 覆盖内容 | 条数 |
|------|----------|------|
| python | Python 语言侧的入门、四类 RPC、代码生成、API 参考 | 5 |
| guides | deadline / retry / 状态码 / 拦截器 / 服务配置等横切能力 | 17 |
| concepts | gRPC 是什么、核心概念（HTTP/2、IDL、四种调用形态） | 3 |
| tooling | protoc 安装、反射调试 | 2 |

## 分区明细

### python

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 跑通第一个 Python gRPC 例子 | [Quick start](https://grpc.io/docs/languages/python/quickstart/) | grpcio、grpcio-tools、helloworld |
| 看四种 RPC 形态的完整 Python 写法 | [Basics tutorial](https://grpc.io/docs/languages/python/basics/) | unary、stream、RouteGuide |
| 查生成的 Python 代码里各符号是什么意思 | [Python generated code](https://grpc.io/docs/languages/python/generated-code/) | pb2、stub、servicer |
| 查 grpcio 的 API 与参数 | [Python API reference](https://grpc.io/docs/languages/python/api/) | channel、server、aio |
| 查 ALTS 认证（GCP 场景） | [Python ALTS](https://grpc.io/docs/languages/python/alts/) | alts、credentials |

### guides

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 设超时并让截止时间自动往下游传 | [Deadlines](https://grpc.io/docs/guides/deadlines/) | deadline、timeout、propagation |
| 配自动重试策略与退避参数 | [Retry](https://grpc.io/docs/guides/retry/) | retryPolicy、maxAttempts、backoff |
| 用对冲请求降低长尾延迟 | [Request hedging](https://grpc.io/docs/guides/request-hedging/) | hedging、tail latency |
| 查标准状态码语义与使用场景 | [Status Codes](https://grpc.io/docs/guides/status-codes/) | UNAVAILABLE、DEADLINE_EXCEEDED |
| 正确构造与传递错误信息 | [Error handling](https://grpc.io/docs/guides/error/) | status、details、rich error |
| 客户端取消后服务端如何收到信号 | [Cancellation](https://grpc.io/docs/guides/cancellation/) | cancel、context |
| 写服务端 / 客户端拦截器（中间件） | [Interceptors](https://grpc.io/docs/guides/interceptors/) | interceptor、middleware、tracing |
| 用 service config 统一配负载均衡与重试 | [Service config](https://grpc.io/docs/guides/service-config/) | methodConfig、loadBalancingConfig |
| 自定义负载均衡策略 | [Custom load balancing](https://grpc.io/docs/guides/custom-load-balancing/) | LB policy、pick_first、round_robin |
| 服务端优雅停机不丢在途请求 | [Server graceful stop](https://grpc.io/docs/guides/server-graceful-stop/) | graceful stop、grace period |
| 标准健康检查协议 | [Health checking](https://grpc.io/docs/guides/health-checking/) | health check、grpc.health.v1 |
| 传 token / 租户 id 这类元数据 | [Metadata](https://grpc.io/docs/guides/metadata/) | metadata、header |
| 配鉴权（TLS / token / mTLS） | [Authentication](https://grpc.io/docs/guides/auth/) | TLS、mTLS、token |
| 长连接保活与断线检测 | [Keepalive](https://grpc.io/docs/guides/keepalive/) | keepalive、ping |
| 消息压缩 | [Compression](https://grpc.io/docs/guides/compression/) | gzip、compression |
| 流控（背压）机制 | [Flow control](https://grpc.io/docs/guides/flow-control/) | flow control、window |
| 性能基准测试方法 | [Benchmarking](https://grpc.io/docs/guides/benchmarking/) | benchmark、qps |

### concepts

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 一句话说清 gRPC 是什么、和 REST 的差别 | [Introduction](https://grpc.io/docs/what-is-grpc/introduction/) | RPC、protobuf、HTTP/2 |
| 查核心概念：IDL、四种调用、channel、stub | [Core concepts](https://grpc.io/docs/what-is-grpc/core-concepts/) | IDL、channel、stub |
| 常见疑问（为什么用 HTTP/2、浏览器支持等） | [FAQ](https://grpc.io/docs/what-is-grpc/faq/) | FAQ、browser、grpc-web |

### tooling

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 装 protoc 编译器 | [protoc installation](https://grpc.io/docs/protoc-installation/) | protoc、install |
| 用反射在运行时探查服务定义 | [Reflection](https://grpc.io/docs/guides/reflection/) | reflection、grpcurl |

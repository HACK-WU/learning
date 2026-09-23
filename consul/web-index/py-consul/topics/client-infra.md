# client-infra（py-consul · 共 8 条）

> 范围：criteo.github.io/py-consul/ · 生成日期：2026-09-22
> 覆盖：客户端基类与连接、异常、回调、Check 构造器、异步客户端 —— 子教程课 1 与课 7 主用

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 `Consul()` 构造参数（host/port/token/scheme/verify/dc） | [consul.base](https://criteo.github.io/py-consul/consul.base.html) | #consul.base.Consul | 构造、连接、token、TLS、dc | |
| 确认 token 有哪几种传法、优先级如何 | [consul.base](https://criteo.github.io/py-consul/consul.base.html) | #consul.base.Consul.prepare_headers | token、鉴权、header | |
| 查底层 HTTP 客户端方法（get/put/post/delete） | [consul.base](https://criteo.github.io/py-consul/consul.base.html) | #consul.base.HTTPClient.get | HTTP、底层、请求 | |
| 查响应封装结构（code/headers/body） | [consul.base](https://criteo.github.io/py-consul/consul.base.html) | #consul.base.Response | 响应、code、headers | |
| 查全部异常类型，写 try/except 兜底 | [consul.exceptions](https://criteo.github.io/py-consul/consul.exceptions.html) | #consul.exceptions.Timeout | 异常、超时、403、404、错误 | |
| 区分超时 / 权限不足 / 键不存在分别捕获什么 | [consul.exceptions](https://criteo.github.io/py-consul/consul.exceptions.html) | #consul.exceptions.NotFound | Timeout、ACLPermissionDenied、NotFound | |
| 查同步客户端入口（默认 `consul.Consul` 实现） | [consul.std](https://criteo.github.io/py-consul/consul.std.html) | #consul.std.Consul | 同步、std、默认客户端 | |
| 用 asyncio 异步客户端 | [consul.aio](https://criteo.github.io/py-consul/consul.aio.html) | | 异步、asyncio、aio | |
| 构造健康检查对象（http/tcp/grpc/ttl/docker/script） | [consul.check](https://criteo.github.io/py-consul/consul.check.html) | #consul.check.Check.http | Check、健康检查、构造器 | [Agent.Check.register](https://criteo.github.io/py-consul/consul.api.agent.html#consul.api.agent.Agent.Check.register) |
| 查响应解析回调（json/bool/binary） | [consul.callback](https://criteo.github.io/py-consul/consul.callback.html) | #consul.callback.CB.json | callback、解析、json | |

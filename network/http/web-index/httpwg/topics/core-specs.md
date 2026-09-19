# core-specs（IETF HTTP WG · 共 15 条）

> 范围：/specs · 生成日期：2026-09-10 · 来源：https://httpwg.org/specs/ 页面导航（人工提取）
> 前 9 条为站点「Core Specifications」分组原样收录；后 6 条为两部大部头（RFC 9110/9111）的章节锚点直达，锚点 id 取自站点页面 HTML 实际返回

## 核心规范

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查方法/状态码/字段/认证的权威语义（HTTP 语义总纲） | [HTTP Semantics (RFC 9110)](https://httpwg.org/specs/rfc9110.html) | | 语义、方法、状态码 | 本文件下半部「章节锚点直达」 |
| 查缓存权威定义（新鲜度/校验/失效/Cache-Control 逐条） | [HTTP Caching (RFC 9111)](https://httpwg.org/specs/rfc9111.html) | | 缓存、新鲜度、校验 | [#validation.model](https://httpwg.org/specs/rfc9111.html#validation.model) |
| 读 HTTP/1.1 报文格式与分帧（消息怎么拆装） | [HTTP/1.1 (RFC 9112)](https://httpwg.org/specs/rfc9112.html) | | 报文、分帧、keep-alive | |
| 读 HTTP/2 规范（二进制分帧/多路复用/队头阻塞的解法） | [HTTP/2 (RFC 9113)](https://httpwg.org/specs/rfc9113.html) | | 多路复用、二进制分帧、流 | [#RFC 7541](https://httpwg.org/specs/rfc7541.html) |
| 读 HTTP/3 规范（QUIC 之上，为什么换 UDP） | [HTTP/3 (RFC 9114)](https://httpwg.org/specs/rfc9114.html) | | QUIC、UDP、0-RTT | [#RFC 9204](https://httpwg.org/specs/rfc9204.html) |
| 读 HPACK：HTTP/2 头压缩算法 | [HPACK (RFC 7541)](https://httpwg.org/specs/rfc7541.html) | | 头压缩、Huffman、动态表 | |
| 读 QPACK：HTTP/3 头压缩（为什么不能照抄 HPACK） | [QPACK (RFC 9204)](https://httpwg.org/specs/rfc9204.html) | | 头压缩、QUIC 乱序 | |
| 读结构化字段（新头该用什么数据类型写） | [Structured Field Values (RFC 9651)](https://httpwg.org/specs/rfc9651.html) | | 结构化字段、Item、Dictionary | |
| 学"在 HTTP 上建协议"的约束与惯例 | [Building Protocols with HTTP (RFC 9205)](https://httpwg.org/specs/rfc9205.html) | | BCP、API 设计 | |

## 章节锚点直达（RFC 9110/9111）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 8 个标准方法各自的规范定义（安全/幂等/可缓存判定） | [RFC 9110](https://httpwg.org/specs/rfc9110.html) | [#method.definitions](https://httpwg.org/specs/rfc9110.html#method.definitions) | 方法、幂等、安全 | |
| 查条件请求规范（If-* 如何求值） | [RFC 9110](https://httpwg.org/specs/rfc9110.html) | [#conditional.requests](https://httpwg.org/specs/rfc9110.html#conditional.requests) | 条件请求、If-None-Match | MDN [Conditional requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Conditional_requests) |
| 查 Range 请求规范（区间怎么切、416 何时回） | [RFC 9110](https://httpwg.org/specs/rfc9110.html) | [#range.requests](https://httpwg.org/specs/rfc9110.html#range.requests) | Range、断点续传 | MDN [Range requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range_requests) |
| 查内容协商规范（服务器驱动的裁决规则） | [RFC 9110](https://httpwg.org/specs/rfc9110.html) | [#content.negotiation](https://httpwg.org/specs/rfc9110.html#content.negotiation) | 内容协商、Accept | |
| 查状态码分类总览（1xx–5xx 各管什么） | [RFC 9110](https://httpwg.org/specs/rfc9110.html) | [#overview.of.status.codes](https://httpwg.org/specs/rfc9110.html#overview.of.status.codes) | 状态码、分类 | |
| 查缓存校验模型（ETag 比对、304 生成规则） | [RFC 9111](https://httpwg.org/specs/rfc9111.html) | [#validation.model](https://httpwg.org/specs/rfc9111.html#validation.model) | 协商缓存、304 | MDN [Caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Caching) |
| 查缓存过期模型（freshness lifetime 计算、启发式缓存） | [RFC 9111](https://httpwg.org/specs/rfc9111.html) | [#expiration.model](https://httpwg.org/specs/rfc9111.html#expiration.model) | 强缓存、过期、启发式 | [#calculating.freshness.lifetime](https://httpwg.org/specs/rfc9111.html#calculating.freshness.lifetime) |
| 查 Cache-Control 字段规范定义（请求/响应指令分列） | [RFC 9111](https://httpwg.org/specs/rfc9111.html) | [#field.cache-control](https://httpwg.org/specs/rfc9111.html#field.cache-control) | Cache-Control、指令 | [#cache-request-directive.max-age](https://httpwg.org/specs/rfc9111.html#cache-request-directive.max-age) |

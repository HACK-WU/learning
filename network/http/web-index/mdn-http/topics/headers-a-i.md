# headers-a-i（MDN HTTP · 共 68 条）

> 范围：/en-US/docs/Web/HTTP/Reference/Headers · 生成日期：2026-09-10 · 来源：站点 sitemap
> 分区为人工再拆（顶层请求/响应头按字母序 A–I / K–Z 两档，非站点原结构；CSP 与 Permissions-Policy 指令页已按站点二级目录单独分出）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看全部请求头/响应头总目录 | [Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers) | | 请求头、响应头、目录 | [#fields.registry](https://httpwg.org/specs/rfc9110.html#fields.registry) |
| 查客户端能接受什么内容类型，内容协商怎么谈 | [Accept](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept) | | 内容协商、MIME、质量因子 | [#field.accept](https://httpwg.org/specs/rfc9110.html#field.accept) |
| 查服务器如何开启客户端提示（Client Hints 上报开关） | [Accept-CH](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-CH) | | 客户端提示、开启 | [Critical-CH](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Critical-CH) |
| 查客户端声明支持哪些压缩编码（gzip/br/zstd） | [Accept-Encoding](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Encoding) | | 压缩、gzip、br | [Content-Encoding](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Encoding) |
| 查客户端偏好的语言与语言协商 | [Accept-Language](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Language) | | 语言、协商、地区 | |
| 查服务器声明接受哪些 PATCH 格式 | [Accept-Patch](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Patch) | | PATCH、格式 | |
| 查服务器声明接受哪些 POST 媒体类型 | [Accept-Post](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Post) | | POST、媒体类型 | |
| 查服务器是否支持 Range 请求（断点续传前提） | [Accept-Ranges](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Ranges) | | 分段、断点续传 | [Range](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range)、[#range.requests](https://httpwg.org/specs/rfc9110.html#range.requests) |
| 查 CORS 凭据模式下通配符为什么不行 | [Access-Control-Allow-Credentials](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Allow-Credentials) | | CORS、凭据、cookie | |
| 查 CORS 预检放行了哪些自定义请求头 | [Access-Control-Allow-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Allow-Headers) | | CORS、预检、请求头 | |
| 查 CORS 允许哪些 HTTP 方法 | [Access-Control-Allow-Methods](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Allow-Methods) | | CORS、预检、方法 | |
| 查 CORS 最核心的响应头（哪些源被放行） | [Access-Control-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Allow-Origin) | | CORS、同源策略、放行源 | |
| 查前端能读到哪些默认读不到的响应头 | [Access-Control-Expose-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Expose-Headers) | | CORS、暴露响应头 | |
| 查预检结果能缓存多久（少发一次 OPTIONS） | [Access-Control-Max-Age](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Max-Age) | | CORS、预检缓存 | |
| 查预检请求里带了哪些将来的请求头 | [Access-Control-Request-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Request-Headers) | | CORS、预检请求 | |
| 查预检请求声明的将来用什么方法 | [Access-Control-Request-Method](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Request-Method) | | CORS、预检请求 | |
| 查嵌入 iframe 的存储访问怎么激活 [待确认] | [Activate-Storage-Access](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Activate-Storage-Access) | | 存储访问、iframe | |
| 查响应在缓存里已经躺了多久 | [Age](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Age) | | 缓存年龄、代理 | [#shared.and.private.caches](https://httpwg.org/specs/rfc9111.html#shared.and.private.caches) |
| 查这个资源支持哪些方法（405 的正确姿势） | [Allow](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Allow) | | 方法、405 | |
| 查服务器通告的备选服务（HTTP/3 迁移入口） | [Alt-Svc](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Alt-Svc) | | 备选服务、HTTP/3 | [#RFC 7838](https://httpwg.org/specs/rfc7838.html) |
| 查这次实际用的备选服务是哪个 [待确认] | [Alt-Used](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Alt-Used) | | 备选服务、调试 | [Alt-Svc](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Alt-Svc) |
| 查归因上报（广告转化）的资格声明 [待确认] | [Attribution-Reporting-Eligible](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Attribution-Reporting-Eligible) | | 归因、广告、隐私 | |
| 查广告来源注册头（归因上报的源端） [待确认] | [Attribution-Reporting-Register-Source](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Attribution-Reporting-Register-Source) | | 归因、来源注册 | |
| 查广告触发注册头（归因上报的触发端） [待确认] | [Attribution-Reporting-Register-Trigger](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Attribution-Reporting-Register-Trigger) | | 归因、触发注册 | |
| 查认证凭据怎么带（Bearer/Basic 的载体） | [Authorization](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Authorization) | | 认证、Bearer、Basic | [#field.authorization](https://httpwg.org/specs/rfc9110.html#field.authorization)、[#auth.scheme.registry](https://httpwg.org/specs/rfc9110.html#auth.scheme.registry) |
| 查客户端缓存里存了哪个压缩字典 [待确认] | [Available-Dictionary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Available-Dictionary) | | 压缩字典、增量压缩 | [Use-As-Dictionary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Use-As-Dictionary) |
| 查强缓存怎么写（max-age/no-cache/no-store 全解） | [Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control) | | 强缓存、max-age、no-store | [#field.cache-control](https://httpwg.org/specs/rfc9111.html#field.cache-control)、[Expires](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Expires) |
| 查怎么一次性清掉站点的 cookie/存储/缓存 | [Clear-Site-Data](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Clear-Site-Data) | | 清缓存、登出 | |
| 查 hop-by-hop 头有哪些（这条是给逐跳用的） | [Connection](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Connection) | | 逐跳、连接管理 | [Keep-Alive](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Keep-Alive) |
| 查图片按设备像素比返回的密度提示 [待确认] | [Content-DPR](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-DPR) | | 像素比、响应式图片 | [DPR](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/DPR) |
| 查响应体摘要怎么校验完整性（Content-Digest） | [Content-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Digest) | | 完整性、摘要 | [Repr-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Repr-Digest)、[#RFC 9530](https://httpwg.org/specs/rfc9530.html) |
| 查下载文件名/内联展示怎么控制 | [Content-Disposition](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Disposition) | | 下载、附件、文件名 | [#RFC 6266](https://httpwg.org/specs/rfc6266.html) |
| 查响应体用了什么压缩（内容编码 vs 传输编码） | [Content-Encoding](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Encoding) | | 压缩、gzip、br | [Accept-Encoding](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Encoding)、[#field.content-encoding](https://httpwg.org/specs/rfc9110.html#field.content-encoding) |
| 查响应体的语言标记 | [Content-Language](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Language) | | 语言、面向受众 | |
| 查请求体到底有多长（服务端怎么读到结尾） | [Content-Length](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Length) | | 长度、请求体 | [#field.content-length](https://httpwg.org/specs/rfc9110.html#field.content-length) |
| 查这条响应对应的是哪个变体 URL | [Content-Location](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Location) | | 内容协商、变体 | |
| 查分段响应里这段是哪个范围 | [Content-Range](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Range) | | 分段、断点续传、206 | [Range](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range) |
| 查 CSP 只上报不拦截模式怎么开 | [Content-Security-Policy-Report-Only](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy-Report-Only) | | CSP、只上报 | [CSP 指令分区](./headers-csp.md) |
| 查请求体/响应体是什么类型（最常背错的头） | [Content-Type](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Type) | | MIME、媒体类型、表单 | [MIME 类型指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types)、[#field.content-type](https://httpwg.org/specs/rfc9110.html#field.content-type) |
| 查 cookie 怎么随请求带上（客户端侧） | [Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cookie) | | cookie、会话 | [Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie)、[#RFC 6265](https://httpwg.org/specs/rfc6265.html) |
| 查关键客户端提示（首跳就带上，不等往返） | [Critical-CH](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Critical-CH) | | 客户端提示、首跳 | [Accept-CH](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-CH) |
| 查跨域隔离怎么做（COEP，配合 SharedArrayBuffer） | [Cross-Origin-Embedder-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Embedder-Policy) | | 跨域隔离、嵌入 | [COOP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Opener-Policy) |
| 查 COEP 只上报模式 | [Cross-Origin-Embedder-Policy-Report-Only](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Embedder-Policy-Report-Only) | | 跨域隔离、只上报 | |
| 查跨域窗口隔离（进程级隔离，防 Spectre） | [Cross-Origin-Opener-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Opener-Policy) | | 跨域隔离、弹窗 | [CORP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Resource-Policy) |
| 查资源允许被谁嵌入加载（图片/脚本防盗链的正解） | [Cross-Origin-Resource-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Resource-Policy) | | 资源策略、嵌入 | [CORS 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS) |
| 查已弃用的"禁止追踪"头的历史 | [DNT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/DNT) | | 隐私、弃用 | [Sec-GPC](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-GPC) |
| 查设备像素比提示（客户端提示旧版） | [DPR](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/DPR) | | 像素比、客户端提示 | [Sec-CH-DPR](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-DPR) |
| 查响应 Date 头的格式与含义 | [Date](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Date) | | 日期、报文时间 | [#field.date](https://httpwg.org/specs/rfc9110.html#field.date) |
| 查设备内存提示（客户端提示） | [Device-Memory](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Device-Memory) | | 设备内存、客户端提示 | [Sec-CH-Device-Memory](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Device-Memory) |
| 查压缩字典的标识符 [待确认] | [Dictionary-ID](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Dictionary-ID) | | 压缩字典、标识 | [Available-Dictionary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Available-Dictionary) |
| 查网络带宽估计提示（客户端提示） | [Downlink](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Downlink) | | 带宽、网络信息 | [ECT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ECT)、[RTT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/RTT) |
| 查有效连接类型枚举（4g/3g…） | [ECT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ECT) | | 连接类型、网络信息 | [Downlink](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Downlink) |
| 查协商缓存的强校验器怎么写（ETag 格式与强弱） | [ETag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ETag) | | 协商缓存、校验器、版本 | [If-None-Match](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-None-Match)、[#field.etag](https://httpwg.org/specs/rfc9110.html#field.etag) |
| 查 TLS 0-RTT 重放风险怎么标 | [Early-Data](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Early-Data) | | 0-RTT、重放 | [#RFC 8470](https://httpwg.org/specs/rfc8470.html) |
| 查 Expect: 100-continue 的机制 | [Expect](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Expect) | | 探路、100 | |
| 查已弃用的证书透明度头的历史 | [Expect-CT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Expect-CT) | | 弃用、证书透明 | |
| 查过期时间怎么写（HTTP/1.0 遗产，和 max-age 谁赢） | [Expires](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Expires) | | 过期、缓存 | [Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control)、[#expiration.model](https://httpwg.org/specs/rfc9111.html#expiration.model) |
| 查代理链路怎么透传真实客户端信息 | [Forwarded](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Forwarded) | | 代理、真实 IP | [X-Forwarded-For](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-For) |
| 查请求里怎么带用户邮箱（爬虫礼仪） | [From](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/From) | | 联系方式、爬虫 | |
| 查 HTTP/1.1 必填的主机头与虚拟主机原理 | [Host](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Host) | | 主机、虚拟主机、必填 | [#field.host](https://httpwg.org/specs/rfc9110.html#field.host) |
| 查幂等键怎么设计（防止重复扣款） | [Idempotency-Key](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Idempotency-Key) | | 幂等、重试、支付 | |
| 查乐观锁怎么写（命中才改） | [If-Match](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-Match) | | 乐观锁、条件请求 | [ETag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ETag)、[#field.if-match](https://httpwg.org/specs/rfc9110.html#field.if-match) |
| 查按修改时间做协商缓存（Last-Modified 搭档） | [If-Modified-Since](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-Modified-Since) | | 协商缓存、时间戳 | [Last-Modified](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Last-Modified)、[#field.if-modified-since](https://httpwg.org/specs/rfc9110.html#field.if-modified-since) |
| 查 304 怎么触发（缓存校验的标配组合） | [If-None-Match](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-None-Match) | | 协商缓存、304、ETag | [ETag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ETag)、[#field.if-none-match](https://httpwg.org/specs/rfc9110.html#field.if-none-match) |
| 查 Range 请求的条件版（资源变了他就失效） | [If-Range](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-Range) | | 断点续传、条件 | [Range](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range)、[#field.if-range](https://httpwg.org/specs/rfc9110.html#field.if-range) |
| 查"没改过才允许改"的条件写法 | [If-Unmodified-Since](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-Unmodified-Since) | | 条件请求、并发写 | [If-Modified-Since](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-Modified-Since) |
| 查子资源完整性强制策略（SRI 头版） [待确认] | [Integrity-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Integrity-Policy) | | 完整性、SRI | |
| 查完整性策略只上报模式 [待确认] | [Integrity-Policy-Report-Only](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Integrity-Policy-Report-Only) | | 完整性、只上报 | |

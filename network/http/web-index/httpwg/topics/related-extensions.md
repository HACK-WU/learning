# related-extensions（IETF HTTP WG · 共 33 条）

> 范围：/specs · 生成日期：2026-09-10 · 来源：https://httpwg.org/specs/ 页面「Related Specifications」分组（6 个 H3 子组原样保留）
> 标题文案为站点页面实际链接文字；标 [待确认] 的条目语义靠标题推断，用前先确认页面内容

## Methods（1 条）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 读 PATCH 方法的规范（部分更新的标准依据） | [PATCH Method (RFC 5789)](https://httpwg.org/specs/rfc5789.html) | | PATCH、部分更新 | MDN [PATCH](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Methods/PATCH) |

## Status Codes（3 条）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 读 428/429/431/511 四个状态码的规范出处 | [Status Codes 428, 429, 431 and 511 (RFC 6585)](https://httpwg.org/specs/rfc6585.html) | | 限流、429、511 | MDN [429](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/429) |
| 读 451 的规范（法律原因屏蔽，致敬《华氏451度》） | [Status Code 451 (RFC 7725)](https://httpwg.org/specs/rfc7725.html) | | 451、法律 | |
| 读 103 Early Hints 的规范（预加载提示） | [Status Code 103 (RFC 8297)](https://httpwg.org/specs/rfc8297.html) | | 103、性能 | |

## Caching Extensions（5 条）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 读 stale-while-revalidate / stale-if-error 的规范（过期后容忍窗口） | [stale-while-revalidate and stale-if-error (RFC 5861)](https://httpwg.org/specs/rfc5861.html) | | SWR、陈旧容忍 | MDN [Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control) |
| 读 immutable 指令的规范（指纹文件永不重验） | [Cache-Control: immutable (RFC 8246)](https://httpwg.org/specs/rfc8246.html) | | immutable、指纹文件 | |
| 读 Cache-Status 的规范（响应经过哪层缓存、命中没有） | [Cache-Status (RFC 9211)](https://httpwg.org/specs/rfc9211.html) | | 缓存观测、命中 | |
| 读 Targeted Cache Control（只对某一层缓存生效的指令） | [Targeted Cache Control Fields (RFC 9213)](https://httpwg.org/specs/rfc9213.html) | | 定向指令、CDN | |
| 读 Cache Groups 的规范（关联资源成组失效） | [HTTP Cache Groups (RFC 9875)](https://httpwg.org/specs/rfc9875.html) | | 缓存组、失效 | |

## Content-Related Extensions（7 条）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 读 Cookie 权威规范（Set-Cookie 属性、路径/域匹配规则） | [Cookies (RFC 6265)](https://httpwg.org/specs/rfc6265.html) | | cookie、会话、SameSite | MDN [Cookies 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cookies) |
| 读 Content-Disposition 的规范（附件/文件名） | [Content-Disposition (RFC 6266)](https://httpwg.org/specs/rfc6266.html) | | 下载、附件 | MDN [Content-Disposition](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Disposition) |
| 读客户端主动声明内容编码的规范（上传压缩） | [Client Initiated Content-Encoding (RFC 7694)](https://httpwg.org/specs/rfc7694.html) | | 上传压缩、编码 | |
| 读 Prefer 的规范（客户端表达"希望"） | [Prefer Header Field (RFC 7240)](https://httpwg.org/specs/rfc7240.html) | | 偏好、异步 | |
| 读 Web Linking 的规范（Link 头分页/预加载） | [Web Linking (RFC 8288)](https://httpwg.org/specs/rfc8288.html) | | Link、分页、rel | |
| 读 Client Hints 的规范（浏览器信息按需上报） | [HTTP Client Hints (RFC 8942)](https://httpwg.org/specs/rfc8942.html) | | 客户端提示、隐私 | MDN [Client hints 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Client_hints) |
| 读压缩字典传输的规范（跨响应复用字典） | [Compression Dictionary Transport (RFC 9842)](https://httpwg.org/specs/rfc9842.html) | | 字典压缩、增量 | MDN [Compression dictionary transport](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Compression_dictionary_transport) |

## Connection and Intermediary Extensions（10 条）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 读 ALPN 头（HTTP/1.1 上 协商应用层协议） | [ALPN Header Field (RFC 7639)](https://httpwg.org/specs/rfc7639.html) | | ALPN、协商 | |
| 读 Alternative Services 的规范（同义服务发现、升级 HTTP/3 的标准路径） | [Alternative Services (RFC 7838)](https://httpwg.org/specs/rfc7838.html) | | Alt-Svc、服务发现 | MDN [Alt-Svc](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Alt-Svc) |
| 读 ORISH 帧（HTTP/2 连接合并的origin确认） | [ORIGIN HTTP/2 Frame (RFC 8336)](https://httpwg.org/specs/rfc8336.html) | | 连接合并、origin | |
| 读 HTTP/2 上跑 WebSocket（RFC 8441，Extended CONNECT） | [Bootstrapping WebSockets with HTTP/2 (RFC 8441)](https://httpwg.org/specs/rfc8441.html) | | WebSocket、h2 | |
| 读 Proxy-Status 的规范（代理错误怎么带回来） | [Proxy-Status (RFC 9209)](https://httpwg.org/specs/rfc9209.html) | | 代理、错误观测 | |
| 读优先级扩展的规范（Priority 头/Time 两套机制） | [Extensible Prioritization Scheme (RFC 9218)](https://httpwg.org/specs/rfc9218.html) | | 优先级、拥塞 | MDN [Priority](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Priority) |
| 读 HTTP/3 上跑 WebSocket（Extended CONNECT over QUIC） | [Bootstrapping WebSockets with HTTP/3 (RFC 9220)](https://httpwg.org/specs/rfc9220.html) | | WebSocket、h3 | 相关：[RFC 9298 Proxying UDP in HTTP](https://www.rfc-editor.org/rfc/rfc9298)（rfc-editor.org，MASQUE 族） |
| 读 Origin 帧（HTTP/3 版连接合并） | [Origin HTTP/3 Frame (RFC 9412)](https://httpwg.org/specs/rfc9412.html) | | h3、连接合并 | |
| 读 Client-Cert 的规范（TLS 客户端证书信息透传给源站） | [Client-Cert HTTP Header Field (RFC 9440)](https://httpwg.org/specs/rfc9440.html) | | 双向 TLS、证书 | |
| 读增量转发的规范（消息字节边收边发） [待确认] | [Incremental Forwarding of HTTP Messages (RFC 10036)](https://httpwg.org/specs/rfc10036.html) | | 增量转发、流式 | |

## Security-Related Extensions（7 条）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 读 Digest 认证的规范（质询-应答，非明文） | [HTTP Digest Access Authentication (RFC 7616)](https://httpwg.org/specs/rfc7616.html) | | Digest、质询应答 | MDN [Authentication 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Authentication) |
| 读 Basic 认证的规范（Base64 而已，必须配 TLS） | [HTTP Basic Authentication (RFC 7617)](https://httpwg.org/specs/rfc7617.html) | | Basic、Base64 | |
| 读加密内容编码（应用层加密，与 TLS 互补） | [Encrypted Content-Encoding (RFC 8188)](https://httpwg.org/specs/rfc8188.html) | | aes128gcm、端到端 | |
| 读 Early Data 的规范（0-RTT 重放风险的标准化防御） | [Using Early Data in HTTP (RFC 8470)](https://httpwg.org/specs/rfc8470.html) | | 0-RTT、重放 | MDN [Early-Data](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Early-Data) |
| 读 HTTP 消息签名的规范（请求签名，API 网关常用） | [HTTP Message Signatures (RFC 9421)](https://httpwg.org/specs/rfc9421.html) | | 签名、Signature、防篡改 | 相关：[在线演示 httpsig.org](https://httpsig.org) |
| 读 Digest Fields 的规范（Content-Digest/Repr-Digest 权威出处） | [Digest Fields (RFC 9530)](https://httpwg.org/specs/rfc9530.html) | | 摘要、完整性 | MDN [Content-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Digest) |
| 读 Concealed Authentication 的规范（TLS 层隐藏认证凭据） [待确认] | [HTTP Concealed Authentication (RFC 9729)](https://httpwg.org/specs/rfc9729.html) | | 隐藏认证、TLS exporter | |

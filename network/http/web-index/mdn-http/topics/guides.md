# guides（MDN HTTP · 共 49 条）

> 范围：/en-US/docs/Web/HTTP/Guides · 生成日期：2026-09-10 · 来源：站点 sitemap
> 概念讲解与报错速查（CORS/SP 错误页按站点子目录原样收录）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看 HTTP 指南总目录 | [Guides](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides) | | 指南、目录 | |
| 学认证体系全景（Basic/Bearer/Cookie/协商的取舍） | [Authentication](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Authentication) | | 认证、鉴权、401 | [Authorization 头](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Authorization)、[#authentication](https://httpwg.org/specs/rfc9110.html#authentication) |
| 查怎么解析 UA 字符串（以及为什么不该解析） | [Browser detection using the user agent](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Browser_detection_using_the_user_agent) | | UA 解析、特性检测 | |
| 学缓存全链路（强缓存/协商缓存/启发式/私有与共享） | [Caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Caching) | | 强缓存、协商缓存、CDN | [Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control)、[#constructing.responses.from.caches](https://httpwg.org/specs/rfc9111.html#constructing.responses.from.caches) |
| 学 Client Hints 体系（低熵/高熵、怎么申请） | [Client hints](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Client_hints) | | 客户端提示、UA 冻结 | [Accept-CH](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-CH) |
| 学压缩（gzip/br、内容编码与分块） | [Compression](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Compression) | | 压缩、gzip、br | [Content-Encoding](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Encoding) |
| 学共享字典压缩（同源资源复用字典） | [Compression dictionary transport](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Compression_dictionary_transport) | | 字典压缩、增量 | [#RFC 9842](https://httpwg.org/specs/rfc9842.html) |
| 学条件请求（If-* 家族与乐观锁写法） | [Conditional requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Conditional_requests) | | 条件请求、ETag、If-Match | [#conditional.requests](https://httpwg.org/specs/rfc9110.html#conditional.requests) |
| 学连接管理（短连接/长连接/流水线的历史） | [Connection management in HTTP/1.x](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Connection_management_in_HTTP_1.x) | | 长连接、队头阻塞 | |
| 学内容协商（Accept 家族怎么谈出结果） | [Content negotiation](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Content_negotiation) | | 内容协商、Accept、Vary | [#content.negotiation](https://httpwg.org/specs/rfc9110.html#content.negotiation) |
| 查各家浏览器默认 Accept 值差异 | [List of default Accept values](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Content_negotiation/List_of_default_Accept_values) | | 默认值、浏览器差异 | |
| 学 cookie 机制（属性、作用域、安全限制） | [Cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cookies) | | cookie、会话、SameSite | [Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie)、[#RFC 6265](https://httpwg.org/specs/rfc6265.html) |
| 学 CORS 全景（同源策略→预检→响应头） | [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS) | | CORS、预检、跨域 | [Access-Control-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Allow-Origin) |
| 看 CORS 报错总目录（控制台报错按名查） | [CORS errors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors) | | CORS 报错、速查 | |
| 查报错：Allow-Origin 与请求 Origin 对不上 | [CORSAllowOriginNotMatchingOrigin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSAllowOriginNotMatchingOrigin) | | Origin 不匹配 | |
| 查报错：网络层就失败了（不是 CORS 配置错） | [CORSDidNotSucceed](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSDidNotSucceed) | | 网络失败、排查 | |
| 查报错：CORS 压根没启用（插件场景） | [CORSDisabled](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSDisabled) | | 未启用 | |
| 查报错：重定向到了外部域不允许 | [CORSExternalRedirectNotAllowed](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSExternalRedirectNotAllowed) | | 外部重定向 | |
| 查报错：Allow-Headers 没放行某请求头 | [CORSInvalidAllowHeader](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSInvalidAllowHeader) | | 请求头未放行 | |
| 查报错：Allow-Methods 没放行某方法 | [CORSInvalidAllowMethod](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSInvalidAllowMethod) | | 方法未放行 | |
| 查报错：带凭据但响应缺 Allow-Credentials | [CORSMIssingAllowCredentials](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSMIssingAllowCredentials) | | 凭据、Allow-Credentials | |
| 查报错：请求方法没有对应处理 | [CORSMethodNotFound](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSMethodNotFound) | | 方法未处理 | |
| 查报错：预检漏放行某自定义头 | [CORSMissingAllowHeaderFromPreflight](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSMissingAllowHeaderFromPreflight) | | 预检、头未放行 | |
| 查报错：响应完全没带 Allow-Origin | [CORSMissingAllowOrigin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSMissingAllowOrigin) | | 缺 Allow-Origin | |
| 查报错：Allow-Origin 写了多个值 | [CORSMultipleAllowOriginNotAllowed](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSMultipleAllowOriginNotAllowed) | | 重复值、通配符误用 | |
| 查报错：带凭据却用了通配符 | [CORSNotSupportingCredentials](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSNotSupportingCredentials) | | 凭据、通配符 | |
| 查报错：请求没带 Origin 头 | [CORSOriginHeaderNotAdded](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSOriginHeaderNotAdded) | | 缺 Origin | |
| 查报错：预检请求本身失败了 | [CORSPreflightDidNotSucceed](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSPreflightDidNotSucceed) | | 预检失败、OPTIONS | |
| 查报错：协议不是 http/https | [CORSRequestNotHttp](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSRequestNotHttp) | | 协议、file:// | |
| 学 CSP 使用全景（策略写法与迁移） | [CSP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP) | | CSP、策略、XSS | [CSP 指令分区](./headers-csp.md) |
| 看 CSP 违规报错总目录 | [CSP errors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP/Errors) | | CSP 报错 | |
| 查报错：页面违反了 CSP 指令 | [CSPViolation](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP/Errors/CSPViolation) | | 违规、上报 | |
| 学资源级跨域策略（CORP 与 COEP 的配合） | [Cross-Origin Resource Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cross-Origin_Resource_Policy) | | CORP、资源嵌入 | [CORP 头](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Resource-Policy) |
| 学 HTTP 版本演进史（0.9→1.0→1.1→2→3 的动机链） | [Evolution of HTTP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Evolution_of_HTTP) | | 版本史、演进 | [#RFC 9112](https://httpwg.org/specs/rfc9112.html)、[#RFC 9114](https://httpwg.org/specs/rfc9114.html) |
| 学 Fetch Metadata（Sec-Fetch-* 怎么防 CSRF） | [Fetch metadata](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Fetch_metadata) | | 请求元数据、CSRF | [Sec-Fetch-Site](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Fetch-Site) |
| 学 iframe 无凭据加载（credentialless） | [IFrame credentialless](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/IFrame_credentialless) | | iframe、无凭据、隔离 | |
| 学报文结构（起行/头/体三段式） | [Messages](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Messages) | | 报文、结构、起行 | [#message.abstraction](https://httpwg.org/specs/rfc9110.html#message.abstraction) |
| 学 MIME 类型体系（text/html 等怎么构成） | [MIME types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types) | | MIME、Content-Type | [#media.type](https://httpwg.org/specs/rfc9110.html#media.type) |
| 查常见 MIME 类型速查表（扩展名→类型） | [Common types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types/Common_types) | | 速查、扩展名 | |
| 学网络错误日志（NEL）机制 | [Network Error Logging](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Network_Error_Logging) | | NEL、错误上报 | [NEL 头](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/NEL) |
| 学 HTTP 全景综述（适用于 HTTP/1.x 与 2 的公共概念） | [Overview](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Overview) | | 综述、组件、代理 | |
| 学 Permissions-Policy 用法（权限委托与 iframe） | [Permissions Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Permissions_Policy) | | 权限策略、iframe | [PP 指令分区](./headers-permissions-policy.md) |
| 学协议升级机制（101 与 Upgrade 的配合） | [Protocol upgrade mechanism](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Protocol_upgrade_mechanism) | | 升级、WebSocket、h2c | [Upgrade 头](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Upgrade) |
| 学代理与隧道（正向代理/网关/CONNECT） | [Proxy servers and tunneling](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Proxy_servers_and_tunneling) | | 代理、隧道、CONNECT | |
| 查 PAC 文件怎么写（自动代理配置） | [Proxy Auto-Configuration (PAC) file](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Proxy_servers_and_tunneling/Proxy_Auto-Configuration_PAC_file) | | PAC、自动代理 | |
| 学 Range 请求（断点续传与并发下载） | [Range requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range_requests) | | 断点续传、206、分片 | [Range 头](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range)、[#range.requests](https://httpwg.org/specs/rfc9110.html#range.requests) |
| 学重定向体系（301/302/307/308 的选择逻辑） | [Redirections](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Redirections) | | 重定向、301、307 | [Location 头](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Location) |
| 学会话管理（cookie 之外的 Web 会话全貌） | [Session](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Session) | | 会话、状态、cookie | |
| 学 UA 冻结与削减（为什么 UA 越来越没信息） | [User-agent reduction](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/User-agent_reduction) | | UA 冻结、客户端提示 | [Sec-CH-UA](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA) |

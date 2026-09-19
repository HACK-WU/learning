# headers-k-z（MDN HTTP · 共 103 条）

> 范围：/en-US/docs/Web/HTTP/Reference/Headers · 生成日期：2026-09-10 · 来源：站点 sitemap
> 分区为人工再拆（顶层请求/响应头按字母序 A–I / K–Z 两档，非站点原结构）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查长连接怎么保活（超时与最大请求数） | [Keep-Alive](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Keep-Alive) | | 长连接、复用 | [Connection](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Connection) |
| 查资源最后修改时间（协商缓存的时间戳） | [Last-Modified](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Last-Modified) | | 协商缓存、修改时间 | [If-Modified-Since](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-Modified-Since)、[#field.last-modified](https://httpwg.org/specs/rfc9110.html#field.last-modified) |
| 查响应体里怎么带超链接（Web Linking 头版） | [Link](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Link) | | 超链接、预加载、分页 | [#RFC 8288](https://httpwg.org/specs/rfc8288.html) |
| 查重定向去哪了 / 新资源在哪（201 的标配） | [Location](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Location) | | 重定向、201、创建 | [#field.location](https://httpwg.org/specs/rfc9110.html#field.location) |
| 查 TRACE 请求最多跳几层 | [Max-Forwards](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Max-Forwards) | | TRACE、跳数 | |
| 查网络错误日志怎么收集（NEL） | [NEL](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/NEL) | | 错误日志、上报 | [Report-To](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Report-To) |
| 查哪些查询参数不影响去重（预取优化） [待确认] | [No-Vary-Search](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/No-Vary-Search) | | 查询参数、预取去重 | |
| 查浏览主题观察声明（Topics API） [待确认] | [Observe-Browsing-Topics](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Observe-Browsing-Topics) | | Topics、广告、隐私 | |
| 查请求来自哪个源（CORS 的钥匙头） | [Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Origin) | | 源、CORS、CSRF | [#http.origin](https://httpwg.org/specs/rfc9110.html#http.origin) |
| 查跨域代理隔离开关 | [Origin-Agent-Cluster](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Origin-Agent-Cluster) | | 站点隔离、域隔离 | |
| 查 Permissions-Policy 只上报模式 | [Permissions-Policy-Report-Only](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy-Report-Only) | | 权限策略、只上报 | [PP 指令分区](./headers-permissions-policy.md) |
| 查 HTTP/1.0 缓存遗产（pragma: no-cache 还有效吗） | [Pragma](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Pragma) | | 缓存、遗产、no-cache | [Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control) |
| 查客户端表达偏好的标准头（Prefer） | [Prefer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Prefer) | | 偏好、异步响应 | [#RFC 7240](https://httpwg.org/specs/rfc7240.html) |
| 查服务器怎么回应 Prefer（被接受了吗） | [Preference-Applied](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Preference-Applied) | | 偏好、回应 | [Prefer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Prefer) |
| 查响应优先级怎么传（RFC 9218） | [Priority](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Priority) | | 优先级、渐进式 | [#RFC 9218](https://httpwg.org/specs/rfc9218.html) |
| 查代理的质询头（407 的搭档） | [Proxy-Authenticate](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Proxy-Authenticate) | | 代理、认证质询 | |
| 查发给代理的凭据（和 Authorization 的分工） | [Proxy-Authorization](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Proxy-Authorization) | | 代理、凭据 | |
| 查往返时延提示（客户端提示） | [RTT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/RTT) | | 时延、网络信息 | [Downlink](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Downlink) |
| 查断点续传怎么发（要哪一段给哪一段） | [Range](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range) | | 分段、断点续传、206 | [Accept-Ranges](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Ranges)、[#field.range](https://httpwg.org/specs/rfc9110.html#field.range) |
| 查 Referer 拼写为什么少了个 r（来源头本体） | [Referer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Referer) | | 来源、防盗链、拼写 | [#field.referer](https://httpwg.org/specs/rfc9110.html#field.referer) |
| 查来源泄露怎么控制（no-referrer 等八档） | [Referrer-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Referrer-Policy) | | 来源策略、隐私 | [Referer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Referer) |
| 查非标准刷新头（<meta refresh 的头版） | [Refresh](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Refresh) | | 刷新、重定向、非标准 | |
| 查错误/日志上报端点怎么登记（旧版） | [Report-To](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Report-To) | | 上报、端点 | [Reporting-Endpoints](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Reporting-Endpoints) |
| 查错误/日志上报端点怎么登记（现役） | [Reporting-Endpoints](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Reporting-Endpoints) | | 上报、端点、CSP | [Report-To](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Report-To) |
| 查整个表示的摘要（和 Content-Digest 的分工） | [Repr-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Repr-Digest) | | 完整性、表示摘要 | [Content-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Digest)、[#RFC 9530](https://httpwg.org/specs/rfc9530.html) |
| 查"等多久再试"怎么告诉客户端（429/503 搭档） | [Retry-After](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Retry-After) | | 重试、限流、退避 | [429](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/429)、[#field.retry-after](https://httpwg.org/specs/rfc9110.html#field.retry-after) |
| 查省流模式声明（Save-Data） | [Save-Data](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Save-Data) | | 省流量、弱网 | |
| 查 Topics API 的观察头（广告兴趣画像） [待确认] | [Sec-Browsing-Topics](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Browsing-Topics) | | Topics、广告、隐私 | |
| 查新版像素比客户端提示 | [Sec-CH-DPR](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-DPR) | | 像素比、客户端提示 | [DPR](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/DPR) |
| 查新版设备内存客户端提示 | [Sec-CH-Device-Memory](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Device-Memory) | | 设备内存、客户端提示 | [Device-Memory](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Device-Memory) |
| 查用户深色模式偏好（客户端提示） | [Sec-CH-Prefers-Color-Scheme](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Prefers-Color-Scheme) | | 深色模式、偏好 | |
| 查减少动效偏好（客户端提示） | [Sec-CH-Prefers-Reduced-Motion](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Prefers-Reduced-Motion) | | 动效、无障碍 | |
| 查降低透明度偏好（客户端提示） | [Sec-CH-Prefers-Reduced-Transparency](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Prefers-Reduced-Transparency) | | 透明度、无障碍 | |
| 查用户代理品牌列表（UA 冻结后的新信源） | [Sec-CH-UA](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA) | | UA 品牌、客户端提示 | [User-Agent](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/User-Agent) |
| 查 CPU 架构提示 | [Sec-CH-UA-Arch](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Arch) | | 架构、x86、arm | |
| 查位宽提示（64/32 位） | [Sec-CH-UA-Bitness](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Bitness) | | 位宽、客户端提示 | |
| 查设备形态提示（桌面/手机/平板） | [Sec-CH-UA-Form-Factors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Form-Factors) | | 设备形态、客户端提示 | |
| 查完整版本号（高熵提示，需 Accept-CH 开启） | [Sec-CH-UA-Full-Version](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Full-Version) | | 版本号、高熵 | |
| 查品牌+完整版本列表（高熵） | [Sec-CH-UA-Full-Version-List](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Full-Version-List) | | 品牌版本、高熵 | |
| 查移动端标记（?1 客户端提示） | [Sec-CH-UA-Mobile](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Mobile) | | 移动端、客户端提示 | |
| 查设备型号提示（高熵） | [Sec-CH-UA-Model](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Model) | | 型号、高熵 | |
| 查操作系统平台提示 | [Sec-CH-UA-Platform](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Platform) | | 平台、Windows、macOS | |
| 查平台版本提示（高熵） | [Sec-CH-UA-Platform-Version](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-Platform-Version) | | 平台版本、高熵 | |
| 查 Windows on ARM 模拟标记 [待确认] | [Sec-CH-UA-WoW64](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA-WoW64) | | 架构模拟、Windows | |
| 查视口高度提示 | [Sec-CH-Viewport-Height](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Viewport-Height) | | 视口、布局 | |
| 查视口宽度提示 | [Sec-CH-Viewport-Width](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Viewport-Width) | | 视口、布局 | |
| 查图片物理宽度提示（旧版） | [Sec-CH-Width](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Width) | | 图片宽度、客户端提示 | [Width](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Width) |
| 查请求目标类型（frame/img/document…） | [Sec-Fetch-Dest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Fetch-Dest) | | Fetch 元数据、目标 | [Fetch metadata 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Fetch_metadata) |
| 查请求模式（navigate/cors/no-cors…） | [Sec-Fetch-Mode](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Fetch-Mode) | | Fetch 元数据、模式 | |
| 查请求发起方与目标的关系（same-origin/cross-site） | [Sec-Fetch-Site](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Fetch-Site) | | Fetch 元数据、CSRF 防御 | |
| 查存储访问状态标记 | [Sec-Fetch-Storage-Access](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Fetch-Storage-Access) | | 存储访问、Fetch 元数据 | |
| 查是否用户触发（防脚本自动请求） | [Sec-Fetch-User](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Fetch-User) | | 用户触发、Fetch 元数据 | |
| 查全局隐私控制声明（GPC） | [Sec-GPC](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-GPC) | | 隐私、拒绝出售 | [DNT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/DNT) |
| 查 Private State Token 系列头本体 [待确认] | [Sec-Private-State-Token](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Private-State-Token) | | 信任令牌、反欺诈 | |
| 查 Private State Token 密码学版本 [待确认] | [Sec-Private-State-Token-Crypto-Version](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Private-State-Token-Crypto-Version) | | 信任令牌、版本 | |
| 查 Private State Token 有效期 [待确认] | [Sec-Private-State-Token-Lifetime](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Private-State-Token-Lifetime) | | 信任令牌、有效期 | |
| 查预取/预渲染声明（Speculation Rules 的头视角） | [Sec-Purpose](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Purpose) | | 预取、预渲染 | [Speculation-Rules](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Speculation-Rules) |
| 查已兑换的信任令牌记录 [待确认] | [Sec-Redemption-Record](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Redemption-Record) | | 信任令牌、兑换 | |
| 查预渲染请求的标签透传 [待确认] | [Sec-Speculation-Tags](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Speculation-Tags) | | 预渲染、标签 | |
| 查服务端怎么回应 WebSocket 握手（101 的钥匙） | [Sec-WebSocket-Accept](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-WebSocket-Accept) | | WebSocket、握手 | [#RFC 8441](https://httpwg.org/specs/rfc8441.html) |
| 查 WebSocket 扩展协商 | [Sec-WebSocket-Extensions](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-WebSocket-Extensions) | | WebSocket、扩展 | |
| 查 WebSocket 握手密钥（防缓存中间盒） | [Sec-WebSocket-Key](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-WebSocket-Key) | | WebSocket、握手密钥 | |
| 查 WebSocket 子协议协商 | [Sec-WebSocket-Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-WebSocket-Protocol) | | WebSocket、子协议 | |
| 查 WebSocket 协议版本 | [Sec-WebSocket-Version](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-WebSocket-Version) | | WebSocket、版本 | |
| 查 Server 头该不该暴露（信息泄露考量） | [Server](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Server) | | 服务器、指纹 | [#field.server](https://httpwg.org/specs/rfc9110.html#field.server) |
| 查服务端各阶段耗时怎么上报（性能归因） | [Server-Timing](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Server-Timing) | | 性能、耗时、监控 | |
| 查 Service Worker 注册响应怎么标 | [Service-Worker](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Service-Worker) | | SW、脚本 | |
| 查 SW 脚本作用域怎么放宽 | [Service-Worker-Allowed](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Service-Worker-Allowed) | | SW、作用域 | |
| 查 SW 导航预加载开关 | [Service-Worker-Navigation-Preload](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Service-Worker-Navigation-Preload) | | SW、预加载 | |
| 查服务端怎么种 cookie（属性全解：Expires/Domain/Secure/HttpOnly/SameSite） | [Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie) | | cookie、会话、SameSite | [Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cookie)、[Cookies 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cookies)、[#RFC 6265](https://httpwg.org/specs/rfc6265.html) |
| 查登录状态怎么告知浏览器（密码管理器联动） [待确认] | [Set-Login](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Login) | | 登录状态、联邦登录 | |
| 查 SourceMap 关联（调试用的旧头） | [SourceMap](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/SourceMap) | | 源映射、调试 | |
| 查预取/预渲染规则下发（JSON 结构） | [Speculation-Rules](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Speculation-Rules) | | 预取、预渲染、性能 | [Sec-Purpose](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-Purpose) |
| 查 HSTS 怎么强制 HTTPS（includeSubDomains/preload） | [Strict-Transport-Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security) | | HTTPS、HSTS、降级防护 | |
| 查哪些加载模式被允许（fenced frame 等） [待确认] | [Supports-Loading-Mode](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Supports-Loading-Mode) | | 加载模式、fenced frame | |
| 查 TE 头（传输编码接受能力，分块相关） | [TE](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/TE) | | 传输编码、 trailers | [Trailer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Trailer)、[#field.te](https://httpwg.org/specs/rfc9110.html#field.te) |
| 查 Timing-Allow-Origin 怎么放开高精度计时 | [Timing-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Timing-Allow-Origin) | | 性能计时、跨域 | |
| 查已弃用的追踪状态头（DNT 的回应版） | [Tk](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Tk) | | 隐私、弃用 | [DNT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/DNT) |
| 查分块响应尾部元数据怎么带 | [Trailer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Trailer) | | 分块、尾部头 | [Transfer-Encoding](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Transfer-Encoding) |
| 查 chunked 传输编码（流式响应怎么算"结束"） | [Transfer-Encoding](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Transfer-Encoding) | | 分块、流式、chunked | [#fields](https://httpwg.org/specs/rfc9110.html#fields) 字段总览 |
| 查协议升级机制（WebSocket/HTTP2 的 Upgrade 流程） | [Upgrade](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Upgrade) | | 升级、WebSocket、h2c | [#field.upgrade](https://httpwg.org/specs/rfc9110.html#field.upgrade) |
| 查 HTTP 明文跳 HTTPS 的自动升级 | [Upgrade-Insecure-Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Upgrade-Insecure-Requests) | | HTTPS、混合内容 | |
| 查压缩字典怎么种到客户端（HTTP 缓存复用） | [Use-As-Dictionary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Use-As-Dictionary) | | 压缩字典、增量压缩 | [Available-Dictionary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Available-Dictionary)、[#RFC 9842](https://httpwg.org/specs/rfc9842.html) |
| 查 UA 头本体（冻结前的历史与冻结后的现状） | [User-Agent](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/User-Agent) | | UA、浏览器识别 | [Sec-CH-UA](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-UA)、[#field.user-agent](https://httpwg.org/specs/rfc9110.html#field.user-agent) |
| 查 Firefox 的 UA 字符串构成实例 | [User-Agent/Firefox](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/User-Agent/Firefox) | | Firefox、UA 构成 | |
| 查缓存为什么要按头分流（Vary 最常见误用） | [Vary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Vary) | | 缓存分流、内容协商 | [#field.vary](https://httpwg.org/specs/rfc9110.html#field.vary) |
| 查报文经过了哪些代理（查链路用） | [Via](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Via) | | 代理链、转发 | [#field.via](https://httpwg.org/specs/rfc9110.html#field.via) |
| 查视口宽度提示（旧版客户端提示） | [Viewport-Width](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Viewport-Width) | | 视口、客户端提示 | [Sec-CH-Viewport-Width](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Viewport-Width) |
| 查认证质询头（401 的搭档，Basic/Digest 格式） | [WWW-Authenticate](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/WWW-Authenticate) | | 认证、质询、401 | [Authorization](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Authorization)、[#field.www-authenticate](https://httpwg.org/specs/rfc9110.html#field.www-authenticate) |
| 查想要哪种摘要算法（协商完整性） | [Want-Content-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Want-Content-Digest) | | 摘要、完整性 | [Content-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Digest) |
| 查想要哪种表示摘要（协商完整性） | [Want-Repr-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Want-Repr-Digest) | | 摘要、表示 | [Repr-Digest](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Repr-Digest) |
| 查已弃用的 Warning 头（缓存警告的历史） | [Warning](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Warning) | | 缓存警告、弃用 | |
| 查图片预期宽度提示（旧版客户端提示） | [Width](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Width) | | 图片宽度、客户端提示 | [Sec-CH-Width](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Sec-CH-Width) |
| 查 MIME 嗅探怎么关（样式表/脚本投毒防护） | [X-Content-Type-Options](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Content-Type-Options) | | nosniff、嗅探、安全 | |
| 查 DNS 预解析开关 | [X-DNS-Prefetch-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-DNS-Prefetch-Control) | | DNS 预解析、性能 | |
| 查 X-Forwarded-For 的格式与伪造问题（Forwarded 的前朝版） | [X-Forwarded-For](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-For) | | 代理、真实 IP、伪造 | [Forwarded](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Forwarded) |
| 查原 Host 被代理改写后怎么找回 | [X-Forwarded-Host](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-Host) | | 代理、原始主机 | |
| 查原始协议是 http 还是 https（代理转发场景） | [X-Forwarded-Proto](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-Proto) | | 代理、协议还原 | |
| 查点击劫持防护（frame-ancestors 的前朝版） | [X-Frame-Options](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options) | | 点击劫持、iframe | [CSP frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors) |
| 查 Flash 时代的跨域策略遗留头 | [X-Permitted-Cross-Domain-Policies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Permitted-Cross-Domain-Policies) | | Flash、遗留 | |
| 查框架/语言指纹头（为什么应该删掉它） | [X-Powered-By](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Powered-By) | | 指纹、信息泄露 | |
| 查 SEO 爬虫指令头（noindex 的头版） | [X-Robots-Tag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Robots-Tag) | | SEO、爬虫、noindex | |
| 查已弃用的 XSS 过滤头（为什么删了它） | [X-XSS-Protection](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-XSS-Protection) | | XSS、弃用、CSP | [CSP 指令分区](./headers-csp.md) |

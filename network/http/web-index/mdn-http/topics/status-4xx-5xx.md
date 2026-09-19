# status-4xx-5xx（MDN HTTP · 共 40 条）

> 范围：/en-US/docs/Web/HTTP · 生成日期：2026-09-10 · 来源：站点 sitemap
> 分区为人工再拆（1xx–3xx / 4xx–5xx 两档，按状态码数值排序，非站点原结构）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 确认 400 Bad Request 的边界（请求本身有问题） | [400](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/400) | | 请求错误、参数 | [422 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/422) |
| 确认 401 和 403 的区别（没认证 vs 没权限） | [401](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/401) | | 未认证、WWW-Authenticate | [403 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/403)、[#auth.scheme](https://httpwg.org/specs/rfc9110.html#auth.scheme) |
| 确认 402 Payment Required 的现状（预留未启用） | [402](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/402) | | 预留、支付 | |
| 确认 403 Forbidden 什么时候返回（有身份但无权限） | [403](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/403) | | 禁止、权限不足 | [401 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/401) |
| 确认 404 的语义与和 410 的区别（不存在 vs 曾经存在） | [404](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/404) | | 未找到、最常见 | [410 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/410) |
| 确认 405 Method Not Allowed（方法用错，Allow 头怎么配） | [405](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/405) | | 方法不允许、Allow | |
| 确认 406 Not Acceptable（内容协商谈不拢） | [406](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/406) | | 内容协商、Accept | |
| 确认 407 Proxy Authentication Required（代理要认证） | [407](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/407) | | 代理、认证 | |
| 确认 408 Request Timeout（客户端发得太慢被掐） | [408](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/408) | | 超时、请求慢 | |
| 确认 409 Conflict（并发更新冲突怎么表达） | [409](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/409) | | 冲突、并发 | |
| 确认 410 Gone（资源已永久消失，SEO 影响与 404 不同） | [410](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/410) | | 已删除、永久 | [404 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/404) |
| 确认 411 Length Required（必须带 Content-Length） | [411](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/411) | | 长度、Content-Length | |
| 确认 412 Precondition Failed（If-Match 等前置条件没过） | [412](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/412) | | 前置条件、乐观锁 | [If-Match](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-Match)、[#conditional.requests](https://httpwg.org/specs/rfc9110.html#conditional.requests) |
| 确认 413 Payload Too Large（请求体超限） | [413](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/413) | | 请求体过大、上传 | |
| 确认 414 URI Too Long（URL 超长的典型成因） | [414](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/414) | | URL 过长、GET 参数 | |
| 确认 415 Unsupported Media Type（Content-Type 不支持） | [415](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/415) | | 媒体类型、Content-Type | |
| 确认 416 Range Not Satisfiable（请求区间越界） | [416](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/416) | | 区间越界、Range | [Range 头](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range) |
| 确认 417 Expectation Failed（Expect 头没被满足） | [417](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/417) | | Expect、失败 | |
| 确认 418 I'm a teapot（彩蛋的来历与真实现状） | [418](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/418) | | 彩蛋、茶壶 | |
| 确认 421 Misdirected Request（连错连接/复用错主机） | [421](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/421) | | 误导、连接复用 | |
| 确认 422 Unprocessable Content（语法对但语义不合法） | [422](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/422) | | 校验失败、语义 | [400 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/400) |
| 确认 423 Locked（WebDAV 资源被锁） | [423](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/423) | | WebDAV、锁定 | |
| 确认 424 Failed Dependency（依赖步骤失败） | [424](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/424) | | 依赖失败、批量 | |
| 确认 425 Too Early（防重放：请求来得太早） | [425](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/425) | | 重放、Early Data | |
| 确认 426 Upgrade Required（必须切换协议） | [426](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/426) | | 协议升级、Upgrade | |
| 确认 428 Precondition Required（强制要求条件请求防丢更新） | [428](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/428) | | 乐观锁、强制条件 | [#RFC 6585](https://httpwg.org/specs/rfc6585.html) |
| 确认 429 Too Many Requests（限流的响应，Retry-After 怎么用） | [429](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/429) | | 限流、重试、Retry-After | [Retry-After](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Retry-After)、[#RFC 6585](https://httpwg.org/specs/rfc6585.html) |
| 确认 431 Request Header Fields Too Large（头太大，Cookie 常见） | [431](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/431) | | 头过大、Cookie | [#RFC 6585](https://httpwg.org/specs/rfc6585.html) |
| 确认 451 Unavailable For Legal Reasons（法律原因屏蔽） | [451](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/451) | | 法律、审查 | [#RFC 7725](https://httpwg.org/specs/rfc7725.html) |
| 确认 500 Internal Server Error（服务端兜底错误） | [500](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/500) | | 服务端错误、异常 | |
| 确认 501 Not Implemented（服务器不认识这个方法/能力） | [501](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/501) | | 未实现、方法 | |
| 确认 502 Bad Gateway（上游挂了/返回非法，网关视角） | [502](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/502) | | 网关、上游崩溃 | [504 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/504) |
| 确认 503 Service Unavailable（过载/维护，Retry-After 配合） | [503](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/503) | | 过载、维护、重试 | [Retry-After](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Retry-After) |
| 确认 504 Gateway Timeout（上游超时，和 502 的分工） | [504](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/504) | | 网关超时、上游慢 | [502 对照](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/502) |
| 确认 505 HTTP Version Not Supported（版本不支持） | [505](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/505) | | 版本、不支持 | |
| 确认 506 Variant Also Negotiates（内容协商配置死循环） | [506](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/506) | | 协商、配置错误 | |
| 确认 507 Insufficient Storage（存储不足，WebDAV） | [507](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/507) | | 存储、WebDAV | |
| 确认 508 Loop Detected（WebDAV 环路检测） | [508](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/508) | | 环路、WebDAV | |
| 确认 510 Not Extended（需要扩展才能处理） | [510](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/510) | | 扩展、策略 | |
| 确认 511 Network Authentication Required（ captive portal 网络登录） | [511](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/511) | | 网络认证、公共 WiFi | [#RFC 6585](https://httpwg.org/specs/rfc6585.html) |

# MDN HTTP 文档 网页索引

> 起始 URL：https://developer.mozilla.org/en-US/docs/Web/HTTP
> 生成日期：2026-09-10 · 范围（scope）：/en-US/docs/Web/HTTP · 条目数：374 · 一次性快照
> 数据来源：站点 sitemap（取自 https://developer.mozilla.org/sitemaps/en-us/sitemap.xml.gz —— 脚本不支持 gzip，由 AI 解压提取；URL 全部为站点实际返回）
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引；标 [待确认] 的条目语义靠 URL 推断，用前先确认页面内容）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建
4. 注意：MDN 已改版为 `Reference/`（参考页）+ `Guides/`（指南页）两大目录，旧的扁平 `/Headers`、`/Status` 路径已不存在

## 高频直达（本课程 15 课最常用的 10 个入口）

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 查某个请求头/响应头的语义与示例 | [Headers 总目录](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers) | headers-a-i / headers-k-z |
| 查 Cache-Control 各指令的语义 | [Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control)（指令级定义见 httpwg 索引） | headers-a-i |
| 查某个状态码该在什么时候返回 | [Status 总目录](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status) | status-1xx-3xx / status-4xx-5xx |
| 学强缓存 vs 协商缓存（ETag/304 全链路） | [Caching 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Caching) + [Conditional requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Conditional_requests) | guides |
| 学 CORS 全套（含 15 种控制台报错速查） | [CORS 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS) + [CORS errors 目录](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors) | guides |
| 查 Cookie/Set-Cookie 属性与安全限制 | [Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie) + [Cookies 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cookies) | headers-k-z / guides |
| 查 Content-Type 与 MIME 类型怎么写 | [Content-Type](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Type) + [常见 MIME 速查](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types/Common_types) | headers-a-i / guides |
| 查 Range/206 断点续传机制 | [Range](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range) + [Range requests 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range_requests) | headers-k-z / guides |
| 查 301/302/307/308 重定向怎么选 | [Redirections 指南](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Redirections) | guides |
| 查 MDN 文档对应哪份 RFC 的哪一节 | [Resources and specifications](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Resources_and_specifications) | overview |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| overview | [topics/overview.md](./topics/overview.md) | 3 | HTTP 文档枢纽页、文档↔RFC 映射（人工归并，非站点原结构） |
| headers-a-i | [topics/headers-a-i.md](./topics/headers-a-i.md) | 68 | 顶层请求/响应头 A–I（Accept/Authorization/Cache-Control/ETag…）· 人工字母拆分 |
| headers-k-z | [topics/headers-k-z.md](./topics/headers-k-z.md) | 103 | 顶层请求/响应头 K–Z（Location/Set-Cookie/Sec-*/X-*…）· 人工字母拆分 |
| headers-csp | [topics/headers-csp.md](./topics/headers-csp.md) | 29 | CSP 首部 + 28 条指令子页（站点二级目录原结构） |
| headers-permissions-policy | [topics/headers-permissions-policy.md](./topics/headers-permissions-policy.md) | 51 | Permissions-Policy 首部 + 50 条指令子页（站点二级目录原结构） |
| status-1xx-3xx | [topics/status-1xx-3xx.md](./topics/status-1xx-3xx.md) | 21 | 信息/成功/重定向状态码 + 总目录（人工按数值段拆分） |
| status-4xx-5xx | [topics/status-4xx-5xx.md](./topics/status-4xx-5xx.md) | 40 | 客户端/服务端错误状态码（人工按数值段拆分） |
| methods | [topics/methods.md](./topics/methods.md) | 10 | 9 个方法 + 总目录（GET/POST/PUT/PATCH/DELETE…） |
| guides | [topics/guides.md](./topics/guides.md) | 49 | 概念指南 + CORS/CSP 报错速查页（缓存/条件请求/Cookie/压缩/报文结构…） |

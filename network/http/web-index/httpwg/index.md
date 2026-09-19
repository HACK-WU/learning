# IETF HTTP Working Group 规范站 网页索引

> 起始 URL：https://httpwg.org/specs/
> 生成日期：2026-09-10 · 范围（scope）：/specs · 条目数：55（覆盖 47 个规范页；其中 13 条为锚点直达路由——8 条 RFC 9110/9111 章节锚点 + 5 条注册表锚点） · 一次性快照
> 数据来源：无 llms.txt / sitemap（已实测 404），自 https://httpwg.org/specs/ 页面导航人工提取，链接与文案均为站点实际返回；RFC 页内锚点 id 取自站点页面 HTML 实际返回
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引；标 [待确认] 的条目语义靠标题推断，用前先确认页面内容）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建
4. RFC 9110（语义）与 RFC 9111（缓存）是查询频率最高的两部大部头——先试本索引的章节锚点直达，再考虑全页抓取（全文很长，锚点能省大量上下文）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 读 HTTP 语义权威定义（方法/状态码/字段） | [RFC 9110 HTTP Semantics](https://httpwg.org/specs/rfc9110.html) | core-specs |
| 读缓存权威定义（新鲜度/校验/失效模型） | [RFC 9111 HTTP Caching](https://httpwg.org/specs/rfc9111.html) + [校验模型锚点](https://httpwg.org/specs/rfc9111.html#validation.model) | core-specs |
| 查 Cache-Control 每个指令的规范定义 | [RFC 9111 §Cache-Control](https://httpwg.org/specs/rfc9111.html#field.cache-control) | core-specs |
| 查某方法/状态码/字段/认证方案是否已注册 | [RFC 9110 注册表群](https://httpwg.org/specs/rfc9110.html#method.registry) | registries |
| 读 HTTP/2 与 HTTP/3 规范本体 | [RFC 9113](https://httpwg.org/specs/rfc9113.html) / [RFC 9114](https://httpwg.org/specs/rfc9114.html) | core-specs |
| 读 Cookie 的权威规范 | [RFC 6265](https://httpwg.org/specs/rfc6265.html) | related-extensions |
| 读认证（Basic/Digest/消息签名）的规范 | [RFC 7617](https://httpwg.org/specs/rfc7617.html) / [RFC 9421](https://httpwg.org/specs/rfc9421.html) | related-extensions |
| 查条件请求/Range 的规范原文 | [RFC 9110 §条件请求](https://httpwg.org/specs/rfc9110.html#conditional.requests) / [§Range](https://httpwg.org/specs/rfc9110.html#range.requests) | core-specs |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| core-specs | [topics/core-specs.md](./topics/core-specs.md) | 17 | 9 部核心规范（9110/9111/9112/9113/9114/HPACK/QPACK/9651/9205）+ RFC 9110/9111 章节锚点直达 8 条 |
| registries | [topics/registries.md](./topics/registries.md) | 5 | 方法/状态码/字段名/认证方案/缓存指令 5 个注册表查重入口（附 IANA 外链） |
| related-extensions | [topics/related-extensions.md](./topics/related-extensions.md) | 33 | 扩展规范 33 部：PATCH/附加状态码/缓存扩展/内容类（Cookie 等）/连接与中间层/安全类 |

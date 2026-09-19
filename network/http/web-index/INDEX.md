# 网页索引登记表

> 涉及下列站点的问题，先查对应条目所在的分区/路由表，再 web_fetch 取正文
> 本表由 topic-teach 集成约定落在本教程目录内（`network/http/web-index/`），覆盖 web-index 技能默认的仓库根 `.web-index/`

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| MDN HTTP 文档 | mdn-http | https://developer.mozilla.org/en-US/docs/Web/HTTP | /en-US/docs/Web/HTTP | 374 | 2026-09-10 |
| IETF HTTP WG 规范站 | httpwg | https://httpwg.org/specs/ | /specs | 55 | 2026-09-10 |
| RFC Editor（TLS、HTTP 历史与中间层规范） | rfc-editor | https://www.rfc-editor.org/ | RFC 9846 / RFC 9849 / RFC 5246 / RFC 5280 / RFC 9525 / RFC 7239 / RFC 1945 / RFC 2068 / RFC 2616 | 9 | 2026-09-15 |
| mkcert 官方仓库 | mkcert | https://github.com/FiloSottile/mkcert | README | 1 | 2026-09-15 |
| Apple Support（Keychain Access） | apple-support | https://support.apple.com/guide/keychain-access/ | 证书信任设置 | 1 | 2026-09-15 |
| curl 官方手册 | curl | https://curl.se/docs/manpage.html | `--write-out` / 压缩 / HTTP 版本 | 4 | 2026-09-15 |
| Chrome DevTools Network | chrome-devtools | https://developer.chrome.com/docs/devtools/network/reference/ | Timing / Waterfall / HAR | 4 | 2026-09-15 |
| WHATWG HTML Standard | whatwg-html | https://html.spec.whatwg.org/multipage/links.html | `preload` / `prefetch` | 3 | 2026-09-15 |

> 快照说明：MDN/httpwg 两站为一次性快照；curl、Chrome DevTools、WHATWG、RFC Editor、mkcert、Apple Support 为课程专项路由。MDN 无 llms.txt，数据取自站点 sitemap（脚本不支持 gzip 由 AI 解压提取）；httpwg 无 llms.txt / sitemap（已实测 404），数据取自 /specs/ 页面导航人工提取。链接失效或站点改版时按站重跑覆盖重建。
> 使用方式：读 `{slug}/index.md` → 按「我要…」列或分区索引定位 → 命中分区只读对应 `topics/{分区}.md` → web_fetch 取正文。

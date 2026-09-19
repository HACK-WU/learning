# headers-csp（MDN HTTP · 共 29 条）

> 范围：/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy · 生成日期：2026-09-10 · 来源：站点 sitemap
> 按站点二级目录拆出（CSP 首部 + 各指令子页，站点原结构）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看 CSP 总览与完整指令清单 | [Content-Security-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy) | | CSP、安全策略、XSS | [只上报模式](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy-Report-Only) |
| 查 <base> 标签允许指向哪 | [base-uri](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/base-uri) | | base、注入 | |
| 查混合内容整页封禁（已废弃的旧开关） | [block-all-mixed-content](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/block-all-mixed-content) | | 混合内容、弃用 | [upgrade-insecure-requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/upgrade-insecure-requests) |
| 查 worker/共享 worker 的加载源白名单 | [child-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/child-src) | | worker、白名单 | [worker-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/worker-src) |
| 查 XHR/fetch/WebSocket 能连哪些域（SSRF 外联收口） | [connect-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/connect-src) | | 接口白名单、外联 | |
| 查兜底指令（未单独配置的 -src 都听它的） | [default-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/default-src) | | 兜底、默认策略 | |
| 查 fenced frame 能加载什么 | [fenced-frame-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/fenced-frame-src) | | fenced frame | |
| 查字体文件允许从哪加载 | [font-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/font-src) | | 字体、白名单 | |
| 查表单能提交到哪（防表单劫持） | [form-action](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/form-action) | | 表单、提交目标 | |
| 查"谁可以把我嵌进 iframe"（反点击劫持现役方案） | [frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors) | | 嵌套白名单、点击劫持 | [X-Frame-Options](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options) |
| 查 iframe 能嵌哪些源 | [frame-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-src) | | iframe、白名单 | [child-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/child-src) |
| 查图片允许从哪加载（含 data: 的取舍） | [img-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/img-src) | | 图片、白名单 | |
| 查 manifest 允许从哪加载 | [manifest-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/manifest-src) | | PWA、清单 | |
| 查音视频允许从哪加载 | [media-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/media-src) | | 音视频、白名单 | |
| 查 object/embed 能加载什么（常直接禁掉） | [object-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/object-src) | | 插件、封禁 | |
| 查预取白名单（Speculation Rules 配套） | [prefetch-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/prefetch-src) | | 预取、白名单 | |
| 查违规上报写到哪（CSP 指令版） | [report-to](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/report-to) | | 上报、端点 | [Reporting-Endpoints](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Reporting-Endpoints) |
| 查已废弃的上报头写法（report-uri） | [report-uri](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/report-uri) | | 上报、弃用 | [report-to](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/report-to) |
| 查强制 Trusted Types（DOM XSS 收口）的要求 | [require-trusted-types-for](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/require-trusted-types-for) | | DOM XSS、注入 | [trusted-types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/trusted-types) |
| 查沙箱指令能锁掉哪些能力（脚本/表单/弹窗） | [sandbox](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/sandbox) | | 沙箱、降权 | |
| 查脚本白名单（nonce/hash/strict-dynamic 三套路） | [script-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src) | | 脚本、nonce、hash | |
| 查内联事件属性脚本的独立白名单 | [script-src-attr](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src-attr) | | 内联脚本、事件属性 | |
| 查 <script> 元素脚本的独立白名单 | [script-src-elem](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src-elem) | | 脚本元素、白名单 | |
| 查样式白名单（style 属性与 <style> 的取舍） | [style-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/style-src) | | 样式、内联 | |
| 查 style 属性的独立白名单 | [style-src-attr](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/style-src-attr) | | style 属性 | |
| 查 <style> 元素的独立白名单 | [style-src-elem](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/style-src-elem) | | style 元素 | |
| 查 Trusted Types 策略名怎么定 | [trusted-types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/trusted-types) | | Trusted Types、策略 | |
| 查页面内 http 资源自动改写 https | [upgrade-insecure-requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/upgrade-insecure-requests) | | 混合内容、自动升级 | |
| 查 worker 脚本白名单 | [worker-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/worker-src) | | worker、白名单 | [child-src](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/child-src) |

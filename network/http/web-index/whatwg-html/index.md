# WHATWG HTML Standard：资源提示索引

> 用途：课 8.3 的 `preload` / `prefetch` 资源提示；这里只取 HTTP 课程需要的资源发现视角。

| 我要解决的问题 | 先看 | 课程落点 |
|---|---|---|
| 当前页面关键资源何时使用 `preload` | [Link type `preload`](https://html.spec.whatwg.org/multipage/links.html#link-type-preload) | 8.3 关键资源提前发现 |
| 未来导航资源何时使用 `prefetch` | [Link type `prefetch`](https://html.spec.whatwg.org/multipage/links.html#link-type-prefetch) | 8.3 未来导航预取 |
| 为什么 preload 可能重复获取 | [Preload processing model](https://html.spec.whatwg.org/multipage/links.html#link-type-preload) | 8.3 `as` / 凭据 / 消费匹配 |

> 核查日期：2026-09。`preload` / `prefetch` 是用户代理提示，不是服务器端 HTTP 响应缓存指令；实际收益要用 Network 记录验证。

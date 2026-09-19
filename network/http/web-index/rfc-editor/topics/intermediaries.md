# 代理链与转发信息主题路由

| 我要解决的问题 | 先看 | 课程落点 |
|---|---|---|
| `Forwarded` 的字段结构与追加顺序 | [RFC 7239 §4](https://www.rfc-editor.org/rfc/rfc7239#section-4) | 9.2 `for` / `by` / `host` / `proto` |
| 为什么不能无条件相信 `Forwarded` | [RFC 7239 §8.1](https://www.rfc-editor.org/rfc/rfc7239#section-8.1) | 9.2 信任边界与伪造 |
| 为什么不应把转发链原样返回给客户端 | [RFC 7239 §8.2](https://www.rfc-editor.org/rfc/rfc7239#section-8.2) | 9.2 信息泄露边界 |

> 核查日期：2026-09。`Forwarded` 的标准规范是 RFC 7239；`X-Forwarded-For` 仍是事实标准，不能把二者混写成同一个字段。

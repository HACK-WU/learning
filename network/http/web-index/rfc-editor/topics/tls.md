# TLS 主题路由

| 我要解决的问题 | 先看 | 课程落点 |
|---|---|---|
| TLS 到底提供哪些安全性质 | [RFC 9846 §1](https://www.rfc-editor.org/rfc/rfc9846#section-1) | 5.1 三大威胁与三种性质 |
| TLS 1.3 一次全握手怎么走 | [RFC 9846 §2](https://www.rfc-editor.org/rfc/rfc9846#section-2) | 5.3 握手与 1-RTT |
| 为什么能有前向保密 | [RFC 9846 §2](https://www.rfc-editor.org/rfc/rfc9846#section-2) | 5.2 临时 `(EC)DHE` 与会话密钥 |
| PSK-only 与 0-RTT 有什么边界 | [RFC 9846 §2](https://www.rfc-editor.org/rfc/rfc9846#section-2) | 5.2/5.3 常见误区 |
| 普通 TLS 的 SNI 为什么可见 | [RFC 9849 §1](https://www.rfc-editor.org/rfc/rfc9849#section-1) | 5.1 握手元数据与隐私边界 |
| ECH 能解决什么、不能解决什么 | [RFC 9849 §3](https://www.rfc-editor.org/rfc/rfc9849#section-3) | 5.1/5.3 SNI 与身份认证的区分 |
| TLS 1.2 握手为何多一轮 | [RFC 5246 §7.3](https://www.rfc-editor.org/rfc/rfc5246#section-7.3) | 5.3 与 TLS 1.3 对照 |

> 核查日期：2026-09。链接由 RFC Editor 提供；具体断言仍以 RFC 正文为准。

# RFC Editor：TLS、HTTP 历史与中间层规范索引

> 用途：HTTP 课程涉及 TLS、HTTPS、前向保密、0-RTT、ECH、代理链与转发头时，先从本索引定位，再打开 RFC 正文核对。

| 我要查什么 | 页面 | 说明 |
|---|---|---|
| TLS 1.3 当前规范 | [RFC 9846](https://www.rfc-editor.org/rfc/rfc9846) | 当前 TLS 1.3 规范；2026-07 发布，替代 RFC 8446 |
| 加密 ClientHello、隐藏 SNI | [RFC 9849](https://www.rfc-editor.org/rfc/rfc9849) | TLS Encrypted Client Hello（ECH）；不替代证书身份校验 |
| TLS 1.2 历史对照 | [RFC 5246](https://www.rfc-editor.org/rfc/rfc5246) | TLS 1.2 规范；用于握手轮次与历史机制对照 |
| X.509/PKIX 证书结构与路径 | [RFC 5280](https://www.rfc-editor.org/rfc/rfc5280) | 证书字段、信任锚、路径验证与约束 |
| TLS 服务身份与主机名校验 | [RFC 9525](https://www.rfc-editor.org/rfc/rfc9525) | SAN、DNS-ID、IP-ID、通配符与 CN 边界；替代 RFC 6125 |
| `Forwarded` 请求头 | [RFC 7239](https://www.rfc-editor.org/rfc/rfc7239) | 代理链传递 `for` / `by` / `host` / `proto`；请求头、可被链上节点修改 |
| HTTP/1.0 历史规范 | [RFC 1945](https://www.rfc-editor.org/rfc/rfc1945) | 课 10.1 的版本演进对照；1996-11 |
| 第一版 HTTP/1.1 规范 | [RFC 2068](https://www.rfc-editor.org/rfc/rfc2068) | 课 10.1 的版本演进对照；1997-01 |
| HTTP/1.1 历史合并规范 | [RFC 2616](https://www.rfc-editor.org/rfc/rfc2616) | 课 10.1 的版本演进对照；1999-06 |

## 高频页面

- [RFC 9846 信息页](https://www.rfc-editor.org/info/rfc9846)
- [RFC 9849 信息页](https://www.rfc-editor.org/info/rfc9849)
- [RFC 5246 信息页](https://www.rfc-editor.org/info/rfc5246)
- [RFC 5280 信息页](https://www.rfc-editor.org/info/rfc5280)
- [RFC 9525 信息页](https://www.rfc-editor.org/info/rfc9525)
- [RFC 7239 信息页](https://www.rfc-editor.org/info/rfc7239)
- [RFC 1945 信息页](https://www.rfc-editor.org/info/rfc1945)
- [RFC 2068 信息页](https://www.rfc-editor.org/info/rfc2068)
- [RFC 2616 信息页](https://www.rfc-editor.org/info/rfc2616)

## 主题路由

- [TLS 握手、PFS、0-RTT 与 ECH](topics/tls.md)
- [证书结构、信任链与身份校验](topics/certificates.md)
- [代理链与转发信息](topics/intermediaries.md)
- [HTTP 版本历史](topics/http-history.md)

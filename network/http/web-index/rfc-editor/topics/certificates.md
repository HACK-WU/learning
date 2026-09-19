# 证书与身份校验主题路由

| 我要解决的问题 | 先看 | 课程落点 |
|---|---|---|
| 证书里有哪些字段 | [RFC 5280 §4.1](https://www.rfc-editor.org/rfc/rfc5280.html#section-4.1) | 6.1 证书结构 |
| 信任链怎样验证 | [RFC 5280 §6.1](https://www.rfc-editor.org/rfc/rfc5280.html#section-6.1) | 6.1 根 CA、中间 CA、叶子证书 |
| 中间 CA 为什么能签发叶子 | [RFC 5280 §4.2.1.9](https://www.rfc-editor.org/rfc/rfc5280.html#section-4.2.1.9) | 6.1 `basicConstraints` 与路径约束 |
| HTTPS 主机名从哪里匹配 | [RFC 9525 §1.3](https://www.rfc-editor.org/rfc/rfc9525.html#section-1.3) | 6.1 SAN、DNS-ID、IP-ID |
| CN 还能不能替代 SAN | [RFC 9525 §1.3](https://www.rfc-editor.org/rfc/rfc9525.html#section-1.3) | 6.1 常见误区 |
| 通配符证书能覆盖几层 | [RFC 9525 §6.3](https://www.rfc-editor.org/rfc/rfc9525.html#section-6.3) | 6.2 域名不匹配排查 |
| 客户端怎样处理身份不匹配 | [RFC 9525 §6.6](https://www.rfc-editor.org/rfc/rfc9525.html#section-6.6) | 6.2 拒绝连接与不要 `-k` |

> 核查日期：2026-09。RFC 5280 负责 PKIX 证书与路径，RFC 9525 负责 TLS 服务身份匹配；二者解决的问题不同，不能互相替代。

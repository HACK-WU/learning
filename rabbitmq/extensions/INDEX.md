# RabbitMQ 扩展内容索引

> 这里收纳“官方索引中存在，但不适合塞进主课 12 课”的专题。扩展不是主课必修；先完成主课和生产运维专项，再按实际场景选读。

## 选择入口

| 你的场景 | 扩展 | 当前状态 | 官方入口 |
|----------|------|----------|----------|
| 需要按 offset、过滤和高吞吐回放 Stream | [Stream 高阶能力](stream-advanced.md) | ✅ 首篇已建立 | [Stream](https://www.rabbitmq.com/docs/stream) · [Stream connections](https://www.rabbitmq.com/docs/stream-connections) |
| 公司统一身份平台是 LDAP / OAuth2 | OAuth2 / LDAP 身份集成 | ⬜ 路由已确认 | [LDAP](https://www.rabbitmq.com/docs/ldap) · [OAuth 2.0](https://www.rabbitmq.com/docs/oauth2) |
| 需要 MQTT / STOMP / WebSocket 接入 | 多协议插件 | ⬜ 路由已确认 | [MQTT](https://www.rabbitmq.com/docs/mqtt) · [STOMP](https://www.rabbitmq.com/docs/stomp) · [Web MQTT](https://www.rabbitmq.com/docs/web-mqtt) |
| 集群需要自动发现或深入 Khepri | 集群形成与元数据存储 | ⬜ 路由已确认 | [Cluster formation](https://www.rabbitmq.com/docs/cluster-formation) · [Metadata store](https://www.rabbitmq.com/docs/metadata-store) |
| 需要查低层协议、man page 或插件 API | 参考资料路由 | ⬜ 仅保留索引 | [AMQP specification](https://www.rabbitmq.com/docs/specification) · [Man pages](https://www.rabbitmq.com/docs/manpages) · [Plugins](https://www.rabbitmq.com/docs/plugins) |

## 为什么不进主线

- OAuth2 / LDAP 的正确落地依赖组织身份系统、证书和 IdP 配置，不能用本地 Docker 示例假装覆盖。
- MQTT / STOMP / Web MQTT 是协议适配器专题，主课核心是 AMQP 0-9-1 与 Python pika；把它们塞入主课会稀释消息模型主线。
- Stream 高阶能力建立在主课已经修正的 AMQP / 专用协议分工之上，适合按事件回放、流过滤和大规模消费者场景选学。
- 集群发现、Khepri 和低层参考资料更偏平台工程或查阅型知识，保留路由比强行写成线性课程更诚实。

## 内容质量规则

1. 每个扩展先写“适用边界”和“不要使用的场景”。
2. 协议、插件和版本行为必须链接到 RabbitMQ 4.3 官方文档。
3. 不能把某个插件的实验结果推广成 RabbitMQ 核心协议结论。

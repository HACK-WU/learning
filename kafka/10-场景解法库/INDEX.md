# Kafka 场景解法库

> **怎么用**：每个场景是一道**开放设计题**。先自己想 30 秒，再展开看解法——**先想后看，能力才长出来**。
> 配套：[08-实战经验.md](../08-实战经验.md)（为什么会崩，学习态）｜ [09-排障速查手册.md](../09-排障速查手册.md)（出错了怎么办，使用态）｜本库（新要求来了怎么设计，设计态）。
> 证据纪律：每条解法均可溯源（Apache Kafka 官方文档 / Confluent 官方文档 / 官方 KIP / 领域公认实践），核查于 2026-08。配置默认值以 **Kafka 4.3** 官方文档为准（当前最新稳定版 4.3.1）。

## 场景清单

| # | 场景 | 类型 | 覆盖知识点 | 链接 |
|---|------|------|-----------|------|
| 1 | 流量涨 10 倍，消费者追不上 | 规模压力题 | 分区数 · 消费者组 · 扩分区代价 | [场景 1](场景-01-消费者追不上.md) |
| 2 | 既要保序又要并发 | 经典设计题 | 分区策略 · 保序粒度 · 迁移 | [场景 2](场景-02-保序与并发.md) |
| 3 | 数据库写 + 发消息的一致性 | 经典设计题 | 交付语义 · outbox · CDC | [场景 3](场景-03-双写一致性.md) |
| 4 | 新业务要消费全部历史数据 | 规模压力题 | 保留策略 · 位移 · 分层存储 | [场景 4](场景-04-历史数据重放.md) |
| 5 | 消息体太大 | 经典设计题 | 生产者批次 · claim check · 压缩 | [场景 5](场景-05-大消息.md) |
| 6 | 跨机房容灾与多活 | 经典设计题 | 副本/ISR · 机架感知 · MirrorMaker 2 | [场景 6](场景-06-跨机房容灾.md) |
| 7 | 事件结构要升级 | 经典设计题 | EDA · 兼容演进 · Schema Registry | [场景 7](场景-07-事件结构演进.md) |
| 8 | 我要"任务队列"语义 | 经典设计题 | 消费模型 · 重试 · share groups | [场景 8](场景-08-任务队列语义.md) |

> 技术域两类场景**各 ≥2**：规模压力题 2 个（场景 1、4）、经典设计题 6 个；合计 8 个，落在 5–8 区间内。
> 每个场景的末尾都有「做错会踩的坑」，回指 [08-实战经验.md](../08-实战经验.md) 的故障模式编号——**设计与故障是一体两面**。

---

## 🧭 遇到没见过的场景？六问思考框架

上面 8 个场景会过时，框架不会。新要求来了，按这六个维度依次过一遍：

| # | 维度 | 要问的问题 | 回指场景 |
|---|------|-----------|---------|
| 1 | **量** | 吞吐/并发的上限由什么决定？这个开关可逆吗？ | [场景 1](场景-01-消费者追不上.md) |
| 2 | **序** | 需要什么粒度的顺序？全局全序还是按 key 有序？ | [场景 2](场景-02-保序与并发.md) |
| 3 | **一致性** | 跨几个系统？Kafka 事务的边界在哪？靠什么收敛？ | [场景 3](场景-03-双写一致性.md) |
| 4 | **时间** | 要保留多久？会不会需要重放？重放时谁受影响？ | [场景 4](场景-04-历史数据重放.md) |
| 5 | **形态** | 消息多大？消息里该装什么？ | [场景 5](场景-05-大消息.md)、[场景 7](场景-07-事件结构演进.md) |
| 6 | **语义** | 是事件流还是任务队列？需要单条确认/延迟/优先级吗？ | [场景 8](场景-08-任务队列语义.md) |

> 可用性维度（[场景 6](场景-06-跨机房容灾.md)）贯穿全部六问——每个方案都要问一句"这个故障域挂了会怎样"。

---

## 📚 官方文档

- [Apache Kafka 4.3 官方文档](https://kafka.apache.org/43/getting-started/)
- [Broker Configs](https://kafka.apache.org/43/configuration/broker-configs/)（`message.max.bytes`、`log.retention.*`、`broker.rack`、`group.share.*`）
- [Producer Configs](https://kafka.apache.org/43/configuration/producer-configs/)（`max.request.size`、`batch.size`、`linger.ms`、`compression.type`、`delivery.timeout.ms`）
- [Tiered Storage](https://kafka.apache.org/43/operations/tiered-storage/)（分层存储的启用方式与限制）
- [Geo-Replication（MirrorMaker 2）](https://kafka.apache.org/43/operations/geo-replication-cross-cluster-data-mirroring/)
- [Confluent · 生产部署最佳实践](https://docs.confluent.io/platform/current/kafka/post-deployment.html)（分区数调整、大消息、机架感知）
- [KIP-932：Queues for Kafka（share groups）](https://cwiki.apache.org/confluence/display/KAFKA/KIP-932%3A+Queues+for+Kafka)
- [microservices.io · Transactional Outbox](https://microservices.io/patterns/data/transactional-outbox.html) ｜ [Debezium · Outbox Event Router](https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html)

---

## 🚀 接下来可以做什么

- **检验设计能力**：复制"考我一下 Kafka，重点考分区设计、交付语义与容灾"——进入知识点对齐（Phase 6）。
- **把设计落地**：对照 [projects/电商订单事件中心](../projects/电商订单事件中心/README.md)，试着用本库的场景改造它（如：加一条 outbox 链路 / 加重试与 DLQ）。
- **查漏补缺**：回看 [08-实战经验.md](../08-实战经验.md) 的上线 Checklist，确认你的设计在投产前每一条都答得上。

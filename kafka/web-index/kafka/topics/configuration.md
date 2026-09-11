# configuration（Apache Kafka 文档 · 共 40 条）

> 范围：`/43/configuration/` · 生成日期：2026-09-10
> 采集自 sitemap 全部 31 条分区条目，本表按「配置页」组织（14 页）+ 课程高频参数直达（17 条）
> **锚点规则已实测**：配置页每个参数都有 `id={页前缀}_{参数名}` 锚点，前缀为 `producerconfigs` / `consumerconfigs` / `brokerconfigs` / `topicconfigs` / `groupconfigs` / `adminclientconfigs` / `remote`（分层存储页）。
> 查单个参数直接用 `https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_acks` 这类 URL，浏览器会滚到该参数。**前缀写错锚点会失效**，新增条目时按上表套用。

## 配置页总览

| 我要… | 去哪一页 | 锚点前缀 | 关键词 |
|-------|----------|----------|--------|
| 查配置总入口 | [Configuration 总览](https://kafka.apache.org/43/configuration/) | — | 配置、入口 |
| 查 Broker 全部配置 | [Broker Configs](https://kafka.apache.org/43/configuration/broker-configs/) | `brokerconfigs` | broker、服务端 |
| 查 Topic 级配置 | [Topic Configs](https://kafka.apache.org/43/configuration/topic-configs/) | `topicconfigs` | topic、主题级 |
| 查生产者全部配置 | [Producer Configs](https://kafka.apache.org/43/configuration/producer-configs/) | `producerconfigs` | producer、生产者 |
| 查消费者全部配置 | [Consumer Configs](https://kafka.apache.org/43/configuration/consumer-configs/) | `consumerconfigs` | consumer、消费者 |
| 查消费者组 / share group 相关配置 | [Group Configs](https://kafka.apache.org/43/configuration/group-configs/) | `groupconfigs` | group、share |
| 查 Admin 客户端配置 | [Admin Configs](https://kafka.apache.org/43/configuration/admin-configs/) | `adminclientconfigs` | admin、管理客户端 |
| 查分层存储配置 | [Tiered Storage Configs](https://kafka.apache.org/43/configuration/tiered-storage-configs/) | `remote` | 分层存储、tiered |
| 查 Kafka Connect 配置 | [Connect Configs](https://kafka.apache.org/43/configuration/kafka-connect-configs/) | `connectconfigs` | connect |
| 查 Kafka Streams 配置 | [Streams Configs](https://kafka.apache.org/43/configuration/kafka-streams-configs/) | `streamsconfigs` | streams |
| 查 MirrorMaker 配置 | [MirrorMaker Configs](https://kafka.apache.org/43/configuration/mirrormaker-configs/) | `mirrormakerconfigs` | MM2、镜像 |
| 查配置提供器（外部注入配置） | [Configuration Providers](https://kafka.apache.org/43/configuration/configuration-providers/) | — | provider、外部配置 |
| 查系统属性（System Properties） | [System Properties](https://kafka.apache.org/43/configuration/system-properties/) | — | 系统属性、JVM |
| 查生产者的"自动生成"配置表（旧版路径） | [Generated Producer Config](https://kafka.apache.org/43/generated/producer_config.html) | — | 旧版、generated |
| 查消费者的"自动生成"配置表（旧版路径） | [Generated Consumer Config](https://kafka.apache.org/43/generated/consumer_config.html) | — | 旧版、generated |
| 查 Topic 的"自动生成"配置表（旧版路径） | [Generated Topic Config](https://kafka.apache.org/43/generated/topic_config.html) | — | 旧版、generated |

## 课程高频参数直达（第 5–9 课 / 排障手册常用）

| 我要查… | 去哪一页 | 相关课程 |
|---------|----------|----------|
| `acks`（第 5 课） | [producer-configs#acks](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_acks) | 课 5 生产者 |
| `enable.idempotence`（第 8 课） | [producer-configs#enable.idempotence](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_enable.idempotence) | 课 8 幂等 |
| `transactional.id`（第 8 课） | [producer-configs#transactional.id](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_transactional.id) | 课 8 事务 |
| `transaction.timeout.ms`（第 8 课） | [producer-configs#transaction.timeout.ms](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_transaction.timeout.ms) | 课 8 事务 |
| `linger.ms`（第 5 课 / 4.0 起默认改 5） | [producer-configs#linger.ms](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_linger.ms) | 课 5、场景解法库 |
| `batch.size` | [producer-configs#batch.size](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_batch.size) | 课 5 |
| `delivery.timeout.ms`（排障：Expiring records） | [producer-configs#delivery.timeout.ms](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_delivery.timeout.ms) | 09 排障 |
| `max.in.flight.requests.per.connection`（幂等约束 ≤5） | [producer-configs#max.in.flight...](https://kafka.apache.org/43/configuration/producer-configs/#producerconfigs_max.in.flight.requests.per.connection) | 课 8 幂等 |
| `enable.auto.commit`（第 6 课） | [consumer-configs#enable.auto.commit](https://kafka.apache.org/43/configuration/consumer-configs/#consumerconfigs_enable.auto.commit) | 课 6 消费者 |
| `auto.offset.reset`（第 6 课 / KIP-1106） | [consumer-configs#auto.offset.reset](https://kafka.apache.org/43/configuration/consumer-configs/#consumerconfigs_auto.offset.reset) | 课 6 |
| `max.poll.interval.ms`（排障：再均衡风暴） | [consumer-configs#max.poll.interval.ms](https://kafka.apache.org/43/configuration/consumer-configs/#consumerconfigs_max.poll.interval.ms) | 09 排障 |
| `max.poll.records` | [consumer-configs#max.poll.records](https://kafka.apache.org/43/configuration/consumer-configs/#consumerconfigs_max.poll.records) | 课 6 |
| `session.timeout.ms`（KIP-735 默认 45s） | [consumer-configs#session.timeout.ms](https://kafka.apache.org/43/configuration/consumer-configs/#consumerconfigs_session.timeout.ms) | 课 6 |
| `group.protocol`（KIP-848 新协议开关） | [consumer-configs#group.protocol](https://kafka.apache.org/43/configuration/consumer-configs/#consumerconfigs_group.protocol) | 课 6 |
| `isolation.level`（事务读隔离，默认 read_uncommitted） | [consumer-configs#isolation.level](https://kafka.apache.org/43/configuration/consumer-configs/#consumerconfigs_isolation.level) | 课 8 |
| `replica.lag.time.max.ms`（第 7 课 ISR，默认 30s） | [broker-configs#replica.lag.time.max.ms](https://kafka.apache.org/43/configuration/broker-configs/#brokerconfigs_replica.lag.time.max.ms) | 课 7 副本 |
| `unclean.leader.election.enable`（第 7 课，默认 false） | [broker-configs#unclean.leader.election.enable](https://kafka.apache.org/43/configuration/broker-configs/#brokerconfigs_unclean.leader.election.enable) | 课 7 |
| `min.insync.replicas`（第 7 课，默认 1） | [broker-configs#min.insync.replicas](https://kafka.apache.org/43/configuration/broker-configs/#brokerconfigs_min.insync.replicas) | 课 7 |
| `log.retention.hours`（默认 168） | [broker-configs#log.retention.hours](https://kafka.apache.org/43/configuration/broker-configs/#brokerconfigs_log.retention.hours) | 课 4、场景解法库 |
| `message.max.bytes`（默认 1048588） | [broker-configs#message.max.bytes](https://kafka.apache.org/43/configuration/broker-configs/#brokerconfigs_message.max.bytes) | 场景解法库 |
| `broker.rack`（机架感知） | [broker-configs#broker.rack](https://kafka.apache.org/43/configuration/broker-configs/#brokerconfigs_broker.rack) | 场景解法库 |
| `group.share.*`（share groups / KIP-932） | [broker-configs#group.share.delivery.count.limit](https://kafka.apache.org/43/configuration/broker-configs/#brokerconfigs_group.share.delivery.count.limit) | 课 10 |
| `remote.log.storage.system.enable`（分层存储，默认关） | [tiered-storage-configs#remote.log.storage.system.enable](https://kafka.apache.org/43/configuration/tiered-storage-configs/#remote_remote.log.storage.system.enable) | 场景解法库 |

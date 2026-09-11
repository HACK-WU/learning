# Apache Kafka 文档 网页索引

> 起始 URL：https://kafka.apache.org/43/ · 生成日期：2026-09-10 · 范围（scope）：`/43/`（4.3 文档） + `documentation/`（当前版长页锚点） + 关键 Javadoc + 课程引用过的 KIP
> **条目数：唯一 URL 126 条（去重后页面 90 个：kafka.apache.org 81 + cwiki.apache.org 9）** · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（配置页带 `#xxx` 锚点可直达参数）
> 采集自 sitemap（`https://kafka.apache.org/sitemap.xml`，站点无 llms.txt）。sitemap 共 2168 条，其中 **2100+ 条是 0.7–4.2 的历史版本快照**——已全部排除，只收 4.3（81 条，与课程采用的 4.3.1 对齐）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节；查单个参数时优先用带锚点的 URL（如 `#producerconfigs_acks`）
3. 本表是快照，链接大面积失效时整站重跑重建

## 时效提醒

- **版本目录会变**：Kafka 发新版后 `/43/` 会被 `/44/` 等取代，届时旧版目录仍在但不再是"当前版"。**事实核查（默认值、新特性）时先确认版本目录是否仍为最新**
- **`/documentation/` 是"当前版"长页**：它永远指向最新版，适合查"不关心版本的通用机制"，但 URL 里的锚点（如 `#producerconfigs`）不保证跨版本稳定
- 想要历史版本：把 `/43/` 换成对应版本目录（如 `/40/` = 4.0），路径结构一致

## 关联索引

- 事实核查闸门：见 `topic-teach` SKILL.md「事实核查闸门」——索引只解决"去哪一页"，不解决"内容是否过时"
- 本地速查：CLI 子命令细节优先 `--help`（如 `kafka-topics.sh --help`），比 fetch 文档快；**本索引未收录 `kafka-*.sh` 单页（官方 4.3 站无独立 CLI 页，已实测 15 个候选路径均 404）**，工具用法查 `operations/basic-kafka-operations` 或容器内 `--help`

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 讲清 Kafka 是什么、解决什么问题 | [Getting Started 总览](https://kafka.apache.org/43/getting-started/) | getting-started |
| 查 Topic / Partition / offset / Broker 官方定义 | [当前版长页 · 概念与术语](https://kafka.apache.org/documentation/#intro_concepts_and_terms) | legacy |
| 本地起 Kafka（Docker / 单机 KRaft） | [Quickstart](https://kafka.apache.org/43/getting-started/quickstart/) | getting-started |
| 用 Docker 起 Kafka | [Docker 快速开始](https://kafka.apache.org/43/getting-started/docker/) | getting-started |
| 查分区、副本、日志的存储模型 | [Log 实现（官方原文）](https://kafka.apache.org/43/implementation/log/) | implementation |
| 查生产者全部配置（acks / linger / batch 等） | [Producer Configs](https://kafka.apache.org/43/configuration/producer-configs/) | configuration |
| 查消费者全部配置（offset 提交 / 超时等） | [Consumer Configs](https://kafka.apache.org/43/configuration/consumer-configs/) | configuration |
| 查 Broker 全部配置（ISR / 副本 / 保留策略） | [Broker Configs](https://kafka.apache.org/43/configuration/broker-configs/) | configuration |
| 查 Topic 级配置（min.insync.replicas 等） | [Topic Configs](https://kafka.apache.org/43/configuration/topic-configs/) | configuration |
| 查 KRaft 仲裁与 controller 运维 | [KRaft 运维](https://kafka.apache.org/43/operations/kraft/) | operations |
| 查 KIP-848 新一代再均衡协议 | [消费者再均衡协议](https://kafka.apache.org/43/operations/consumer-rebalance-protocol/) | operations |
| 查事务协议与 EOS 机制 | [事务协议](https://kafka.apache.org/43/operations/transaction-protocol/) | operations |
| 查监控指标与 JMX | [监控](https://kafka.apache.org/43/operations/monitoring/) | operations |
| 写 Java 生产者代码（API 与官方示例） | [KafkaProducer Javadoc](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/producer/KafkaProducer.html) | javadoc |
| 写 Java 消费者代码（API 与官方示例） | [KafkaConsumer Javadoc](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/KafkaConsumer.html) | javadoc |
| 查某个 KIP 的原文与动机 | [KIP 总索引](https://cwiki.apache.org/confluence/spaces/KAFKA/pages/50859233/Kafka+Improvement+Proposals) | kip |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| getting-started | [topics/getting-started.md](./topics/getting-started.md) | 10 | 入门总览、Quickstart、Docker、使用场景、生态、升级、版本兼容、ZK→KRaft 迁移 |
| design-implementation | [topics/design-implementation.md](./topics/design-implementation.md) | 12 | 设计动机、协议规范、日志/分发/网络层/消息格式等底层实现 |
| configuration | [topics/configuration.md](./topics/configuration.md) | 40 | 配置页总览（16 行）+ broker / topic / producer / consumer 等课程高频参数直达锚点 |
| operations | [topics/operations.md](./topics/operations.md) | 18 | 基础运维、KRaft、监控、事务协议、再均衡、跨集群镜像、硬件与 OS、多租户、ELR、分层存储 |
| connect-streams | [topics/connect-streams.md](./topics/connect-streams.md) | 12 | Kafka Connect 概览与用户/开发指南、Streams 概念/架构/开发指南 |
| security | [topics/security.md](./topics/security.md) | 7 | 安全总览、SASL 认证、SSL 加密、ACL 授权、监听器配置、运行中集群接入安全 |
| javadoc | [topics/javadoc.md](./topics/javadoc.md) | 14 | 生产者/消费者/Admin 客户端核心类与事务相关异常类 |
| legacy | [topics/legacy.md](./topics/legacy.md) | 16 | `documentation/` 当前版长页锚点（课程已引用 8 条）+ 版本锁定迁移建议表 |
| kip | [topics/kip.md](./topics/kip.md) | 10 | 课程事实核查引用过的 KIP 原文 + KIP 总索引 |

> 上表条数为各分区**明细行**合计（同一页面会在多个分区重复出现，如 `getting-started/` 既在本区高频直达也在 topics/getting-started）。
> **去重后真实规模：唯一 URL 126 条 / 唯一页面 90 个**（kafka.apache.org 81，其中 `/43/` 下 79 个 + 顶层 2 个；cwiki.apache.org 9 个）。以去重口径为准。

# legacy（当前版长页 `documentation/` · 共 16 条）

> 范围：`https://kafka.apache.org/documentation/`（**当前版**长页）· 生成日期：2026-09-10
> 这 8 条是 **Kafka 课程已成文讲义里实际引用过的链接**（见 `00-学习档案.md` 事实核查记录与学生可见的 📚 官方文档区块），全部已实测 HTTP 200
> ⚠️ 为什么单独成一区：它**永远指向最新版**（不锁 4.3），好处是"查通用机制不必关心版本"，坏处是**参数默认值与新特性会随版本漂移**。
> **做事实核查（默认值 / 新特性）时改查 `/43/` 下的版本锁定页**（见 configuration / operations 分区），本区只用于"沿用了课程原链接"的场景。

| 我要… | 去哪一页 | 锚点 | 关键词 | 用在哪 |
|-------|----------|------|--------|--------|
| 查当前版文档首页 | [Kafka Documentation](https://kafka.apache.org/documentation/) | — | 文档首页、当前版 | 课 2、4、9 |
| 查 Topic / Partition / Broker / offset 官方定义 | [概念与术语](https://kafka.apache.org/documentation/#intro_concepts_and_terms) | `#intro_concepts_and_terms` | 概念、术语 | 课 4 |
| 查生产者配置（长页版） | [Producer Configs](https://kafka.apache.org/documentation/#producerconfigs) | `#producerconfigs` | producer、acks、linger | 课 5、8 |
| 查消费者配置（长页版） | [Consumer Configs](https://kafka.apache.org/documentation/#consumerconfigs) | `#consumerconfigs` | consumer、offset 提交 | 课 6、8、实战项目 |
| 查 Broker 配置（长页版） | [Broker Configs](https://kafka.apache.org/documentation/#brokerconfigs) | `#brokerconfigs` | broker、ISR、副本 | 课 7 |
| 查 Topic 级配置（长页版） | [Topic Configs](https://kafka.apache.org/documentation/#topicconfigs) | `#topicconfigs` | min.insync.replicas | 课 7 |
| 查运维章节（长页版） | [Operations](https://kafka.apache.org/documentation/#operations) | `#operations` | 运维、监控 | 08 实战经验 |
| 查使用场景（长页版） | [Use Cases](https://kafka.apache.org/documentation/#uses) | `#uses` | 场景、用例 | 课 10 |

## 迁移建议

新课 / 新核查**不必再引用本区长页链接**，改用版本锁定的 `/43/` 页：

| 本区（当前版，会漂移） | 建议改用（锁 4.3） |
|------------------------|---------------------|
| `#producerconfigs` | [/43/configuration/producer-configs/](https://kafka.apache.org/43/configuration/producer-configs/) |
| `#consumerconfigs` | [/43/configuration/consumer-configs/](https://kafka.apache.org/43/configuration/consumer-configs/) |
| `#brokerconfigs` | [/43/configuration/broker-configs/](https://kafka.apache.org/43/configuration/broker-configs/) |
| `#topicconfigs` | [/43/configuration/topic-configs/](https://kafka.apache.org/43/configuration/topic-configs/) |
| `#intro_concepts_and_terms` | [/43/getting-started/introduction/](https://kafka.apache.org/43/getting-started/introduction/) |
| `#uses` | [/43/getting-started/uses/](https://kafka.apache.org/43/getting-started/uses/) |
| `#operations` | [/43/operations/](https://kafka.apache.org/43/operations/) |

> 已有讲义里的长页链接**不必批量替换**（它们仍 200 可用），只在下次修订该课时顺手换成锁定版。

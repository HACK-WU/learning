# kip（Kafka Improvement Proposals · 共 10 条）

> 范围：`cwiki.apache.org/confluence/display/KAFKA/` · 生成日期：2026-09-10
> **KIP 不在 kafka.apache.org 的 sitemap 里**，本表按 `00-学习档案.md`「事实核查记录」中实际引用过的 KIP 整理，**每条已实测 HTTP 200**
> KIP 是"某机制为什么引入、默认值何时改变"的**一手出处**——官方文档只给结论（"默认是 X"），KIP 才给理由与版本线。核查"从哪个版本开始默认变了"这类问题时，KIP 比文档更有用。

| 我要… | 去哪一页 | 关键词 | 用在哪个结论 |
|-------|----------|--------|--------------|
| 找某个 KIP 的原文（总索引） | [KIP 总索引](https://cwiki.apache.org/confluence/spaces/KAFKA/pages/50859233/Kafka+Improvement+Proposals) | 索引、入口 | 通用 |
| 查幂等与事务的诞生（0.11.0.0，2017-06-28） | [KIP-98：Exactly Once Delivery and Transactional Messaging](https://cwiki.apache.org/confluence/display/KAFKA/KIP-98+-+Exactly+Once+Delivery+and+Transactional+Messaging) | 幂等、事务、EOS | 课 8 交付语义 |
| 查 Streams EOS 语义 | [KIP-129：Streams Exactly-Once Semantics](https://cwiki.apache.org/confluence/display/KAFKA/KIP-129%3A+Streams+Exactly-Once+Semantics) | Streams、EOS | 课 8 |
| 查生产者默认最强交付保证（3.0 起 enable.idempotence + acks=all） | [KIP-679：Producer will enable the strongest delivery guarantee by default](https://cwiki.apache.org/confluence/display/KAFKA/KIP-679%3A+Producer+will+enable+the+strongest+delivery+guarantee+by+default) | 默认幂等、acks=all | 课 5、8、9 |
| 查粘性分区器（2.4.0 引入并默认，替代轮询） | [KIP-480：Sticky Partitioner](https://cwiki.apache.org/confluence/display/KAFKA/KIP-480%3A+Sticky+Partitioner) | 分区策略、粘性 | 课 5 分区策略 |
| 查新一代消费者再均衡协议（4.0 GA，增量式） | [KIP-848：The Next Generation of the Consumer Rebalance Protocol](https://cwiki.apache.org/confluence/display/KAFKA/KIP-848%3A+The+Next+Generation+of+the+Consumer+Rebalance+Protocol) | 再均衡、KIP-848 | 课 6 |
| 查 EOS 的生产者可扩展性（sendOffsets 事务化，KIP-447） | [KIP-447：Producer scalability for exactly once semantics](https://cwiki.apache.org/confluence/display/KAFKA/KIP-447%3A+Producer+scalability+for+exactly+once+semantics) | 事务、组元数据 | 课 8、实战项目 |
| 查挂起事务的检测与中止工具（kafka-transactions.sh） | [KIP-664：Provide tooling to detect and abort hanging transactions](https://cwiki.apache.org/confluence/display/KAFKA/KIP-664%3A+Provide+tooling+to+detect+and+abort+hanging+transactions) | 挂起事务、CLI | 课 8 |
| 查消费者 session.timeout.ms 默认值上调（45s） | [KIP-735：Increase default consumer session timeout](https://cwiki.apache.org/confluence/display/KAFKA/KIP-735%3A+Increase+default+consumer+session+timeout) | session 超时 | 课 6、9 |
| 查 share groups / Queues for Kafka（4.0 EA→4.1 Preview→4.2 GA） | [KIP-932：Queues for Kafka](https://cwiki.apache.org/confluence/display/KAFKA/KIP-932%3A+Queues+for+Kafka) | share group、队列、单条确认 | 课 10、场景解法库 |

## URL 书写注意（踩过的坑）

cwiki 的 KIP 页面标题**分隔符不统一**，实测：

- **KIP-98** 用 `+-+`（加号）分隔：`KIP-98+-+Exactly+Once+Delivery+and+Transactional+Messaging` → 200
- **其余 KIP** 用 `%3A+`（冒号 URL 编码）分隔：`KIP-848%3A+The+Next+Generation...` → 200

两种写法**不能互换**：把 KIP-848 写成 `KIP-848+-+...` 实测 **404**。
新增 KIP 条目时，**先照抄上表格式再 curl 验一次**，或直接从 [KIP 总索引](https://cwiki.apache.org/confluence/spaces/KAFKA/pages/50859233/Kafka+Improvement+Proposals) 点进去取真实 URL——**不要按规律拼**。

> 课程事实核查还提到 KIP-1106（`auto.offset.reset` 的 by_duration 选项），其实测 URL 返回 404（标题写法与推测不符），**故未收录**；需要时从总索引搜索 "KIP-1106" 取真实链接。

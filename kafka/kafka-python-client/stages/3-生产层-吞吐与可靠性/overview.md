# 阶段 3 · 生产层 · 吞吐与可靠性

> 一句话：**理解是为了选型，生产是为了扛住量、不丢数据**。

## 本阶段要解决的冲突

你的服务上了线，量一起来就扛不住——要么吞吐上不去，要么为了吞吐把可靠性丢了。你开始怀疑"是不是该换库"，但换库意味着重写，你不敢赌。

> ⚠️ **2026-09-21 更正**：原文称"事务 EOS 是 librdkafka 独占能力，kafka-python 给不了"——**此说法已被课 8 实测推翻**。
> `kafka-python 3.0.11` 五个事务方法（`init_transactions` / `begin_transaction` / `commit_transaction` / `abort_transaction` / `send_offsets_to_transaction`）**全部存在且能真跑**：abort 后 `read_committed` 读到 0 条、僵尸实例 fencing 正常抛 `ProducerFencedError`、全链路 consume-transform-produce 零重复。
> **真正没有事务的是 `kafka-python-ng 2.2.3`**（五个方法全无，连 `transactional_id` 配置项都没有）。
> 保留 confluent 的理由因此改为**性能**而非能力：单事务开销 confluent 20.5 ms vs kafka-python 108.5 ms（5.3 倍差距）。详见 [课 8](课8-事务与恰好一次.md)。

> ⚠️ **2026-09-22 更正**：原文称"Schema Registry 是 confluent-kafka 独占能力"——**此说法表述不准，已被课 9 实测修正**。
> 准确说法是：**SR 客户端是 confluent-kafka 独占**（`schema_registry` 子包及其 serializer），但**Avro 序列化本身两库都能做**——`kafka-python` 配 `fastavro` 手工拼 wire format 可跑通完整端到端（v1/v2 混合 10/10）。
> 另外，此前判断"`schema_registry` 子包不存在"也是**误判**：子包在，缺的是 `certifi`/`httpx`/`authlib`/`cachetools`/`googleapis-common-protos` 五个依赖（wheel 不自带）。
> `kafka-python` 真正缺的是**集中式兼容性校验的治理能力**，不是序列化能力。详见 [课 9](课9-序列化与SchemaRegistry.md)。

本阶段用 `confluent-kafka` 打正面战场。选它的理由是**高吞吐**（课 7 实测 10~13x）、**事务开销低**（课 8 实测单事务 20.5 ms vs 108.5 ms），以及**Schema Registry 生态开箱可用**（课 9 实测）。

## 课程

| 课 | 标题 | 核心问题 | 状态 |
|---|---|---|---|
| 课 7 | 吞吐调优与压缩（🧪 实测） | 两库差多少，调优参数怎么配 | ✅ 已讲解（2026-09-21） |
| 课 8 | 事务与恰好一次 | EOS 三库都能做吗，边界在哪 | ✅ 已讲解（2026-09-21） |
| 课 9 | 序列化与 Schema Registry（🧪 实测） | 消息格式怎么演进而不炸 | ✅ 已讲解（2026-09-22） |
| 课 10 | 消费者工程与并发模型 | 消费端怎么扩，GIL 怎么绕 | ✅ 已讲解（2026-09-23） |

## 本阶段产出

- 一份本机实测的两库吞吐对照（已有预研数据）
- 一套事务/EOS 的可运行实现
- 序列化演进的兼容性判据
- 消费者并发模型选型

## 预研期实测结论（摘要）

> 完整数据与脚本见 [assets/bench/RESULTS.md](../../assets/bench/RESULTS.md)

| 场景 | confluent-kafka | kafka-python | 倍数 |
|---|---|---|---|
| 生产（1KB，acks=all，6 分区 3 副本） | 33,827 ~ 106,821 msg/s | 5,272 ~ 6,851 msg/s | 4.9x ~ 16.0x |
| 消费 | 662,125 ~ 1,084,582 msg/s | 72,419 ~ 85,394 msg/s | 8.3x ~ 14.5x |

⚠️ 注意：**倍数是区间不是定值**。confluent 波动达 3 倍（对机器负载敏感），kafka-python 反而极稳定（早早撞天花板后稳定输出）。正文写作时须如实说明这一点。

## 导航

- ⬆️ 返回：[Kafka Python 客户端子教程目录](../../02-课程目录.md)
- ⬅️ 上一阶段：[阶段 2 · 理解层](../2-理解层-协议与源码/overview.md)
- ➡️ 下一阶段：[阶段 4 · 生产级集成](../4-生产级集成/overview.md)
- 📖 进度：[00-学习档案](../../00-学习档案.md)

# 课 3 · AdminClient 与元数据治理

> 一句话：**不收发一条消息，只用代码把集群管起来 —— 建删 topic、查元数据、算消费组 lag**。

## 你将学到什么

- 三库 AdminClient 的能力边界（**aiokafka 也有，但顶层不导出**）
- Topic 生命周期全流程，以及**同一库内返回结构都不统一**的坑
- 消费组与位移查询：**kafka-python 完全没有这块能力**，必须 confluent
- **lag 怎么算**（运维最核心的指标）

## 先修

- [课 2：三库横评与 API 对照](./课2-三库横评与API对照.md)：已经会用 `hasattr` 探 API 存在性

---

## 一、三库 AdminClient：能力边界实测

### 🔴 先纠正一个容易犯的错：aiokafka 有没有 AdminClient？

我第一版这么查：

```python
import aiokafka
[n for n in dir(aiokafka) if "Admin" in n]   # → []
```

**结论错了。** `aiokafka/__init__.py` 的 `__all__` 根本没导出它：

```python
# aiokafka 顶层 __all__
['AIOKafkaProducer', 'AIOKafkaConsumer', 'AIOKafkaClient',
 'ConsumerRebalanceListener', 'ConsumerStoppedError', 'IllegalOperation',
 'ConsumerRecord', 'TopicPartition', 'OffsetAndTimestamp', 'OffsetAndMetadata']
```

正确查法是进子模块：

```python
from aiokafka.admin import AIOKafkaAdminClient   # ✓ 存在
# aiokafka.admin 模块导出：AIOKafkaAdminClient, NewPartitions, NewTopic, RecordsToDelete
```

而且它**能力齐全**——实测 10 个常用 Admin API **全部存在**（比 kafka-python 还多）：

```text
存在: create_topics, delete_topics, list_topics, describe_topics,
      list_consumer_groups, list_consumer_group_offsets,
      describe_consumer_groups, create_partitions, describe_configs, alter_configs
缺失: []
```

> ⚠️ **教训**："顶层 `dir()` 查不到" ≠ "不存在"。查能力要进子模块 / 看包目录（`aiokafka/admin/` 是真实存在的）。这和评审清单第 11 条「先探明结构再下结论」是同一条。

### 三库 Admin 能力对照

| API | kafka-python | confluent | aiokafka |
|---|:---:|:---:|:---:|
| `create_topics` / `delete_topics` / `list_topics` | ✓ | ✓ | ✓ |
| `describe_topics` / `create_partitions` | ✓ | ✓ | ✓ |
| `describe_configs` / `alter_configs` | ✓ | ✓ | ✓ |
| `describe_cluster` / ACL 三件套 | ✓ | ✓ | — |
| **`list_consumer_groups`** | **✗** | ✓ | ✓ |
| **`list_consumer_group_offsets`** | **✗** | ✓ | ✓ |
| **`describe_consumer_groups`** | **✗** | ✓ | ✓ |
| **`delete_consumer_groups`** | **✗** | ✓ | ✓ |
| **`alter_consumer_group_offsets`** | **✗** | ✓ | ✓ |
| **`list_offsets`** | **✗** | ✓ | — |
| 调用方式 | 同步 | 同步 | `await` |

实测报错原文：

```text
AttributeError: 'KafkaAdminClient' object has no attribute 'list_consumer_groups'
```

> 🔑 **选型硬约束**：**要做消费组治理，kafka-python 直接出局**（5 个消费组 API 一个都没有）。这是课 1「分层」之外新增的一条判据——**管理面能力**也要纳入选型。

---

## 二、Topic 生命周期：同一库内返回结构都不统一

这是本课最让人意外的发现。课 2 已经知道 3.0.11 的 `create_topics` 返回 `{'topics':[...]}`。但**同一个 AdminClient 里，每个操作返回的东西都不一样**：

| 操作 | 返回类型 | 结构 |
|---|---|---|
| `create_topics` | `dict` | `{'topics': [{'name', 'error_code', 'topic_id', ...}]}` |
| `delete_topics` | `dict` | 同上 |
| `list_topics` | `list[str]` | `['sec-ops-demo', '__consumer_offsets', ...]` |
| `describe_topics` | `list[dict]` | 分区数组叫 `partitions`，分区号字段是 `partition_index` |
| `create_partitions` | **响应对象** | `CreatePartitionsResponse(version=3, results=[...])` |
| `describe_configs` | `dict` | `{'topic': {name: {...}}}` |

实测原文（`describe_topics` 的完整结构）：

```json
[{
  "error_code": 0, "name": "l3-shapes", "topic_id": "c44f6d94-...",
  "is_internal": false,
  "partitions": [
    {"error_code": 0, "partition_index": 1, "leader_id": 1,
     "leader_epoch": 0, "replica_nodes": [1], "isr_nodes": [1], "offline_replicas": []},
    {"error_code": 0, "partition_index": 0, "leader_id": 3,
     "leader_epoch": 0, "replica_nodes": [3], "isr_nodes": [3], "offline_replicas": []}
  ],
  "authorized_operations": ["READ", "WRITE", "CREATE", ...]
}]
```

> 🔴 **我踩的坑**：第一版写 `p['partition']` 拿分区号 → `KeyError: 'partition'`。正确是 **`partition_index`**（分区数组本身的 key 才叫 `partitions`）。
> 判据：**拿不准就先 `json.dumps` 把结构打出来**，别猜字段名。

### 幂等性：重复建同名 topic

实测**显式抛异常**（这个还算好）：

```text
TopicAlreadyExistsError: [Error 36] TopicAlreadyExistsError:
  Request 'CreateTopicsRequest(version=7, topics=[CreatableTopic(n...
```

但注意 `create_topics` 本身**不抛**——它返回 `error_code`。所以：

```python
r = admin.create_topics([NewTopic(t, ...)])
for item in r["topics"]:                    # 不是 {topic: Future}
    if item.get("error_code") != 0:         # 静默失败在这里
        raise RuntimeError(f"{item['name']} 失败: {item.get('error_message')}")
```

### 删除是异步的吗？

实测本集群（Kafka 4.0.0）**删除后第 1 次查询就不存在了**：

```text
第 1 次查询: l3-lifecycle 存在 = False
```

但**不能依赖这个**——删除在 Kafka 里是异步的，大规模集群可能有延迟。生产代码要做轮询确认。

---

## 三、消费组与位移查询：kafka-python 出局，用 confluent

### 先造出真实的组与位移

```python
# 1. 建 topic（2 分区），发 10 条
p = KafkaProducer(bootstrap_servers=BS)
for i in range(10):
    p.send(TOPIC, f"msg-{i}".encode(), partition=i % 2)
p.flush()

# 2. 只消费 6 条就关掉 → 故意留 4 条 lag
c = KafkaConsumer(TOPIC, group_id=GROUP, auto_offset_reset="earliest", ...)
for i, msg in enumerate(c):
    if i >= 5: break
c.close()
```

### confluent 查询（2.15 的真实签名）

**两个坑**（我都踩了）：

```python
# 坑 1：describe_consumer_groups 返回 dict，不是 Future
res = cf.describe_consumer_groups([GROUP])     # ← 直接是 dict
#   cf.describe_consumer_groups([G]).result()  → AttributeError: 'dict' object has no attribute 'result'

# 坑 2：list_consumer_group_offsets 在 2.15 要传对象，不是字符串
from confluent_kafka import ConsumerGroupTopicPartitions
cg = ConsumerGroupTopicPartitions(GROUP, [TopicPartition(TOPIC, 0), TopicPartition(TOPIC, 1)])
res = cf.list_consumer_group_offsets([cg])
#   传 [GROUP] 字符串 → TypeError: Expected list of 'ConsumerGroupTopicPartitions'
```

实测输出：

```text
=== confluent 查消费组 ===
  组数 = 2
    - l3-demo-group   state=ConsumerGroupState.EMPTY
    - l3-demo-group2  state=ConsumerGroupState.EMPTY

--- describe_consumer_groups ---
    返回 dict（注意：不是 Future）
    group=l3-demo-group2
      state    = ConsumerGroupState.EMPTY
      protocol = None
      members  = 0

--- list_consumer_group_offsets（2.15 新签名）---
    返回 dict
    group=l3-demo-group2  分区数=2
      l3-group-demo2-0: offset=1
      l3-group-demo2-1: offset=5
```

### 🎯 lag 怎么算（本课最有运维价值的部分）

**lag = log-end offset − committed offset**。两段代码配合：

```python
# 1. 拿 log-end（用 Consumer 的 get_watermark_offsets）
probe = Consumer({"bootstrap.servers": BS, "group.id": "lag-probe"})
lo, hi = probe.get_watermark_offsets(TopicPartition(TOPIC, 0))   # hi 就是 log-end

# 2. 拿 committed（用 AdminClient）
res = cf.list_consumer_group_offsets([ConsumerGroupTopicPartitions(
        GROUP, [TopicPartition(TOPIC, 0), TopicPartition(TOPIC, 1)])])
for gid, fut in res.items():
    for tp in fut.result().topic_partitions:
        committed[tp.partition] = tp.offset

# 3. 相减
lag = hi - committed[pid]
```

实测结果（我故意留的 4 条 lag 被准确算出来了）：

```text
--- lag 计算 ---
  分区      committed     log-end     lag
  0         1             5           4      ← 故意留的
  1         5             5           0
  总 lag = 4
```

> 💡 `get_watermark_offsets` 一次返回 `(low, high)`，**同时替代** `beginning_offsets` / `end_offsets`——呼应课 2 的对照表。

---

## 四、元数据治理的检查清单

| 场景 | 用什么 | 注意 |
|---|---|---|
| 建 topic 后确认成功 | 检查 `error_code`，**不抛异常** | 静默失败高发区 |
| 重复建同名 | 会抛 `TopicAlreadyExistsError`（Error 36） | 但 `create_topics` 内部不抛 |
| 查分区分布 | `describe_topics` → `partitions[].leader_id/isr_nodes` | 字段是 `partition_index` |
| 删 topic 后确认 | 轮询 `list_topics` | 异步删除，别假设立刻生效 |
| 查消费组 | **必须 confluent**（kafka-python 无此能力） | 2.15 要传 `ConsumerGroupTopicPartitions` |
| 算 lag | log-end（watermark）− committed | 两者要分开取 |

---

## 一句话记住

> **kafka-python 做不了消费组治理**（5 个 API 全无），管理面需求直接选 confluent；AdminClient 的**返回结构在同一库内都不统一**（dict / list / 响应对象三种），拿不准就 `json.dumps` 打出来看，别猜字段名。

## 常见误区

| 误区 | 真相 |
|---|---|
| "aiokafka 没有 AdminClient" | 有，在 `aiokafka.admin` 子模块；顶层 `__all__` 没导出，导致 `dir(aiokafka)` 查不到 |
| "`create_topics` 失败会抛异常" | 不抛。返回 `error_code`，要自己检查 |
| "字段名猜一下就行" | `describe_topics` 的分区号字段是 `partition_index`，猜 `partition` 直接 KeyError |
| "confluent 的方法都返回 Future" | `describe_consumer_groups` 直接返回 dict，调 `.result()` 反而报错 |
| "lag 查一下就有" | Kafka 不直接给 lag。要 log-end − committed，两处分别取 |

## 本课实测资产

| 脚本 | 用途 |
|---|---|
| [`verify_admin_api.py`](../../assets/bench/verify_admin_api.py) | 三库 Admin API 存在性矩阵 |
| [`verify_aiokafka_admin.py`](../../assets/bench/verify_aiokafka_admin.py) | 纠正"aiokafka 无 AdminClient"的误判 |
| [`verify_topic_lifecycle.py`](../../assets/bench/verify_topic_lifecycle.py) | Topic 生命周期 + 幂等性 + 异步删除 |
| [`verify_admin_shapes.py`](../../assets/bench/verify_admin_shapes.py) | **各操作真实返回结构**（本课核心） |
| [`verify_consumer_group2.py`](../../assets/bench/verify_consumer_group2.py) | 消费组查询 + **lag 计算**（2.15 正确签名） |
| [`run_group_check.sh`](../../assets/bench/run_group_check.sh) | 执行入口 |

## 下一步

- 阶段 2 课 4：生产者内部机制 —— 批次累加、Sender 线程、acks 与重试链路

## 导航

- ⬅️ 上一课：[课 2 三库横评与 API 对照](./课2-三库横评与API对照.md)
- ⬆️ 返回：[阶段 1 概览](./overview.md) · [课程目录](../../02-课程目录.md)
- 📖 进度：[00-学习档案](../../00-学习档案.md)

# 吞吐基准实测结论（课 7 事实依据）

> 本文所有数字均为**本机实测**，非引用网上 benchmark。
> 实测日期：2026-09-20　环境：WSL2 Ubuntu / Docker / CPython 3.12

## 一、为什么必须自己实测

网上流传的 Python Kafka 客户端性能数据**不可信**，实测检索到的 2025-2026 年"benchmark"存在硬伤：

- 出现 `kafka-python EOS 950k > confluent-kafka 800k` 这类结论——纯 Python 反超 C 实现，违背基本常识
- 数据来源集中在内容农场站点，标注"2025 internal tests"却无可复现方法
- 同一指标在不同页面互相矛盾（有说 confluent 5-10x，有说 kafka-python 更快）

按项目铁律「先核验再下结论」，**结论一律以本机实测为准**。

## 二、实测环境

| 项 | 值 |
|---|---|
| 客户端运行位置 | Docker 容器 `kafka-pybench:3.12`，接入 `stage6-observability_kafka-net` |
| Python | CPython 3.12.14（官方 `python:3.12-slim`） |
| 依赖管理 | uv（官方 `ghcr.io/astral-sh/uv` 镜像） |
| confluent-kafka | **2.15.1**（librdkafka 2.15.1） |
| kafka-python-ng | **2.2.3** |
| 集群 | 3 节点 KRaft，apache/kafka:4.0.0，6 分区 / 3 副本 |
| 消息 | 1KB 固定体，100,000 条/轮 |
| 确认语义 | `acks=all`（最严，与生产一致） |
| 压缩 | 关闭（基线轮） |
| 采样 | 5 轮 |

### 一个必踩的坑：advertised.listeners

broker 的 `KAFKA_ADVERTISED_LISTENERS` 配的是容器名 `kafka-1:9092`。
客户端拿到这个地址后，若跑在宿主机上直连 `19192`，**会因地址不可达而失败**。

**解法**：让客户端容器接入同一 docker 网络，用容器名连接。
（与课 15 实测记录的是同一个坑。）

## 三、实测结果

### 生产吞吐（msg/s）

| 轮次 | confluent-kafka | kafka-python-ng | 倍数 |
|---|---|---|---|
| 1 | 33,827 | 6,851 | 4.9x |
| 2 | 47,960 | 6,270 | 7.6x |
| 3 | 56,525 | 5,272 | 10.7x |
| 4 | 76,027 | 5,799 | 13.1x |
| 5 | 106,821 | 6,660 | 16.0x |
| **区间** | **33,827 ~ 106,821** | **5,272 ~ 6,851** | **4.9x ~ 16.0x** |

### 消费吞吐（msg/s）

| 轮次 | confluent-kafka | kafka-python-ng | 倍数 |
|---|---|---|---|
| 1 | 697,380 | 84,089 | 8.3x |
| 2 | 984,104 | 73,499 | 13.4x |
| 3 | 662,125 | 74,383 | 8.9x |
| 4 | 1,052,123 | 72,419 | 14.5x |
| 5 | 1,084,582 | 85,394 | 12.7x |
| **区间** | **662,125 ~ 1,084,582** | **72,419 ~ 85,394** | **8.3x ~ 14.5x** |

## 四、结论

1. **confluent-kafka 在吞吐上确实有量级优势**：生产 5~16 倍，消费 8~15 倍。用户"高吞吐有优势"的判断**被实测证实**。
2. **kafka-python 的绝对性能非常稳定**（5,272~6,851 msg/s，波动 <30%），而 confluent 波动大（33k~107k，3 倍区间）。
   → confluent 对机器负载更敏感，kafka-python 则早早撞到自己的天花板。
3. **结论只报区间，不报单次最优**——这是本项目的一贯要求（跑 3-5 次取范围）。

## 五、实测中踩到的三个脚本级坑（都是"结论失真"级别的）

这些若不修，实测出来的数字是**假的**，而且假得很隐蔽：

### 坑 1：confluent 的 `consume()` 会等满 timeout

`consumer.consume(num_messages=10000, timeout=5.0)` **不管是否拿够 10000 条，都会等满 5 秒**。
诊断实测：拿 1999 条耗时 5.00 秒 → 计算出 400 msg/s 的假象。

**修正**：以"拿到最后一条消息的时刻"作为计时终点，而非循环外计时。

```python
last_msg_at = start
while received < NUM_MESSAGES:
    msgs = consumer.consume(num_messages=10000, timeout=1.0)
    ...
    last_msg_at = time.perf_counter()
elapsed = last_msg_at - start
```

### 坑 2：kafka-python 的 `compression_type` 不接受字符串 `"none"`

传 `"none"` 抛 `ValueError: Not supported codec: none`，必须传 `None`。
（confluent 侧是 `compression.type="none"`，字符串合法——两库 API 不一致的典型例子。）

### 坑 3：confluent 的 `delete_topics` 的 future 参数不能按关键字传

`delete_topics([t], future=None, operation_timeout=15)` 抛
`TypeError: argument for function given by name ('future') and position (2)`。
**去掉 `future` 参数**即可。

## 六、复现方法

```bash
# 1. 构建镜像（uv + 两库）
docker build -t kafka-pybench:3.12 assets/bench/

# 2. 跑一轮（默认 10 万条）
bash assets/bench/run-bench.sh 1 100000
```

脚本位置：[bench_confluent.py](bench_confluent.py) /
[bench_kafka_python.py](bench_kafka_python.py) /
[run-bench.sh](run-bench.sh)

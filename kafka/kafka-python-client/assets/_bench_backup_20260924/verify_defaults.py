"""课 2：配置项默认值核验方法 —— 这是本课最有复用价值的方法论。

核心问题：不同库对「同一件事」的默认值不同，且文档未必说全。
方法：不要相信文档，直接读运行时的默认值。

核验对象（最容易踩坑的几个）：
  - acks            （可靠性）
  - enable.idempotence（幂等）
  - auto.offset.reset（消费起点）
  - enable.auto.commit（自动提交）
  - max.poll.records（单次拉取条数）
  - compression.type（压缩）
"""

# ---------- 1. confluent-kafka：配置对象自带默认值 ----------
print("=" * 70)
print("1. confluent-kafka：读运行期默认值")
print("=" * 70)
from confluent_kafka import Consumer, Producer

KEYS = [
    "acks",
    "enable.idempotence",
    "compression.type",
    "linger.ms",
    "batch.size",
    "max.in.flight.requests.per.connection",
    "retries",
    "transactional.id",
]

# Producer 默认配置
p_conf = Producer({"bootstrap.servers": "kafka-1:9092"})
print("--- Producer 默认值 ---")
for k in KEYS:
    try:
        v = p_conf.conf.get(k)
        print(f"  {k:<45} = {v!r}")
    except Exception as e:
        print(f"  {k:<45} 读取失败 {type(e).__name__}")

CKEYS = [
    "auto.offset.reset",
    "enable.auto.commit",
    "auto.commit.interval.ms",
    "max.poll.records",
    "session.timeout.ms",
    "heartbeat.interval.ms",
    "group.id",
    "isolation.level",
]
c_conf = Consumer({"bootstrap.servers": "kafka-1:9092",
                   "group.id": "probe"})
print("\n--- Consumer 默认值 ---")
for k in CKEYS:
    try:
        v = c_conf.conf.get(k)
        print(f"  {k:<45} = {v!r}")
    except Exception as e:
        print(f"  {k:<45} 读取失败 {type(e).__name__}")

# ---------- 2. kafka-python：默认配置在 DEFAULT_CONFIG ----------
print("\n" + "=" * 70)
print("2. kafka-python：DEFAULT_CONFIG")
print("=" * 70)
from kafka import KafkaConsumer, KafkaProducer
from kafka.producer.kafka import DEFAULT_CONFIG as P_DEFAULT

print("--- KafkaProducer DEFAULT_CONFIG（关键项）---")
kp_keys = {
    "acks": "acks",
    "enable_idempotence": "enable.idempotence",
    "compression_type": "compression.type",
    "linger_ms": "linger.ms",
    "batch_size": "batch.size",
    "max_in_flight_requests_per_connection": "max.in.flight.requests.per.connection",
    "retries": "retries",
}
for py_key, std_key in kp_keys.items():
    v = P_DEFAULT.get(py_key, "（未定义）")
    print(f"  {std_key:<45} = {v!r}   [python名: {py_key}]")

print("\n--- KafkaConsumer DEFAULT_CONFIG（关键项）---")
from kafka.consumer.kafka import DEFAULT_CONFIG as C_DEFAULT

kc_keys = {
    "auto_offset_reset": "auto.offset.reset",
    "enable_auto_commit": "enable.auto.commit",
    "auto_commit_interval_ms": "auto.commit.interval.ms",
    "max_poll_records": "max.poll.records",
    "session_timeout_ms": "session.timeout.ms",
    "heartbeat_interval_ms": "heartbeat.interval.ms",
    "group_id": "group.id",
    "isolation_level": "isolation.level",
}
for py_key, std_key in kc_keys.items():
    v = C_DEFAULT.get(py_key, "（未定义）")
    print(f"  {std_key:<45} = {v!r}   [python名: {py_key}]")

# ---------- 3. aiokafka ----------
print("\n" + "=" * 70)
print("3. aiokafka：用 inspect.signature 读默认值")
print("=" * 70)
import inspect

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

print("--- AIOKafkaProducer 签名默认值 ---")
sig = inspect.signature(AIOKafkaProducer.__init__)
for name in ["acks", "enable_idempotence", "compression_type",
             "linger_ms", "batch_size", "max_batch_size"]:
    if name in sig.parameters:
        print(f"  {name:<45} = {sig.parameters[name].default!r}")

print("\n--- AIOKafkaConsumer 签名默认值 ---")
sig2 = inspect.signature(AIOKafkaConsumer.__init__)
for name in ["auto_offset_reset", "enable_auto_commit",
             "auto_commit_interval_ms", "max_poll_records",
             "session_timeout_ms", "heartbeat_interval_ms",
             "group_id", "isolation_level"]:
    if name in sig2.parameters:
        print(f"  {name:<45} = {sig2.parameters[name].default!r}")

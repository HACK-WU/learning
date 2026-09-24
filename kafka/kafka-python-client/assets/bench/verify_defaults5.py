"""课 2：配置项默认值核验 v5 —— 最终版（kafka-python 的 DEFAULT_CONFIG 是类属性）。

四版踩坑全记录（本课最好的素材）：
  v1: Producer 无 .conf 属性；kafka.producer.kafka 模块级无 DEFAULT_CONFIG → ImportError
  v2: kafka.consumer.kafka 模块不存在（正确是 kafka.consumer.group）
  v3: 两库用 **kwargs，inspect.signature 查不到
  v4: 找模块级 dict 找不到
  v5: 【正确】DEFAULT_CONFIG 是「类属性」→ KafkaProducer.DEFAULT_CONFIG
      源码位置：kafka/producer/kafka.py:405、kafka/consumer/group.py:299

方法论沉淀：默认值位置因库而异，按库选入口：
  - kafka-python：类属性 DEFAULT_CONFIG
  - confluent   ：不暴露（**kwargs 透传 librdkafka）→ 用「非法值报错」反推 key，默认值看文档
  - aiokafka    ：显式签名 → inspect.signature
"""
from kafka import KafkaConsumer, KafkaProducer
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
import inspect

KEYS = {
    "acks": "acks",
    "enable_idempotence": "enable.idempotence",
    "compression_type": "compression.type",
    "linger_ms": "linger.ms",
    "batch_size": "batch.size",
    "max_in_flight_requests_per_connection": "max.in.flight.requests.per.connection",
    "retries": "retries",
    "auto_offset_reset": "auto.offset.reset",
    "enable_auto_commit": "enable.auto.commit",
    "auto_commit_interval_ms": "auto.commit.interval.ms",
    "max_poll_records": "max.poll.records",
    "session_timeout_ms": "session.timeout.ms",
    "heartbeat_interval_ms": "heartbeat.interval.ms",
    "group_id": "group.id",
    "isolation_level": "isolation.level",
}


def dump_kp(cls, label, keys):
    cfg = getattr(cls, "DEFAULT_CONFIG", None)
    print(f"\n--- {label}（{len(cfg) if cfg else 0} 项默认配置）---")
    if not cfg:
        print("  无 DEFAULT_CONFIG")
        return {}
    got = {}
    for pyk in keys:
        if pyk in cfg:
            got[pyk] = cfg[pyk]
            print(f"  {KEYS[pyk]:<42} = {cfg[pyk]!r}")
    return got


print("=" * 78)
print("kafka-python 默认值（类属性 DEFAULT_CONFIG）")
print("=" * 78)
kp_p = dump_kp(KafkaProducer, "KafkaProducer",
               ["acks", "enable_idempotence", "compression_type",
                "linger_ms", "batch_size",
                "max_in_flight_requests_per_connection", "retries"])
kp_c = dump_kp(KafkaConsumer, "KafkaConsumer",
               ["auto_offset_reset", "enable_auto_commit",
                "auto_commit_interval_ms", "max_poll_records",
                "session_timeout_ms", "heartbeat_interval_ms",
                "group_id", "isolation_level"])

print()
print("=" * 78)
print("aiokafka 默认值（inspect.signature）")
print("=" * 78)
ak = {}
for cls, label, keys in [
    (AIOKafkaProducer, "AIOKafkaProducer",
     ["acks", "enable_idempotence", "compression_type",
      "linger_ms", "batch_size"]),
    (AIOKafkaConsumer, "AIOKafkaConsumer",
     ["auto_offset_reset", "enable_auto_commit",
      "auto_commit_interval_ms", "max_poll_records",
      "session_timeout_ms", "heartbeat_interval_ms",
      "isolation_level"]),
]:
    print(f"\n--- {label} ---")
    sig = inspect.signature(cls.__init__)
    for k in keys:
        if k in sig.parameters:
            d = sig.parameters[k].default
            d = "（必填）" if d is inspect.Parameter.empty else d
            ak[k] = d
            print(f"  {k:<42} = {d!r}")

print()
print("=" * 78)
print("⚠️ 关键差异：kafka-python vs aiokafka 默认值不一致的项")
print("=" * 78)
PAIR = [("acks", "acks"), ("enable_idempotence", "enable_idempotence"),
        ("compression_type", "compression_type"), ("linger_ms", "linger_ms"),
        ("auto_offset_reset", "auto_offset_reset"),
        ("enable_auto_commit", "enable_auto_commit"),
        ("auto_commit_interval_ms", "auto_commit_interval_ms"),
        ("max_poll_records", "max_poll_records"),
        ("session_timeout_ms", "session_timeout_ms"),
        ("heartbeat_interval_ms", "heartbeat_interval_ms"),
        ("isolation_level", "isolation_level")]
found = False
for pyk, akk in PAIR:
    a = kp_p.get(pyk, kp_c.get(pyk, "—"))
    b = ak.get(akk, "—")
    if a != "—" and b != "—" and repr(a) != repr(b):
        print(f"  {pyk:<34} kafka-python={a!r:<20} aiokafka={b!r}")
        found = True
if not found:
    print("  （本次比对未发现不一致）")

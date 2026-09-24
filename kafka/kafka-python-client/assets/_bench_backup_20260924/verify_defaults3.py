"""课 2：配置项默认值核验 v3 —— 用「真能拿到值」的方法。

v1/v2 踩的坑（都是本课素材）：
  1. confluent Producer 没有 .conf（cimpl.Producer 不暴露）
     → 正确方法：Consumer 有 .conf 吗？实测。或用 list_topics 间接。
     → 最可靠：confluent 提供 `Producer()` 内部配置不可读，
       改用「构造时报错」或「文档对照 + 行为验证」。
  2. kafka-python consumer 模块是 kafka.consumer.group（不是 .kafka）
  3. kafka 包没有 DEFAULT_CONFIG，默认值写在 __init__ 签名里

结论方法论：
  - 默认值在「类/函数的签名」里 → inspect.signature 最通用
  - 三库统一用 signature，不要各自猜内部结构
"""
import inspect

from confluent_kafka import Consumer as CfConsumer
from confluent_kafka import Producer as CfProducer
from kafka import KafkaConsumer, KafkaProducer
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

STD = {
    "acks": "acks",
    "enable_idempotence": "enable.idempotence",
    "compression_type": "compression.type",
    "linger_ms": "linger.ms",
    "batch_size": "batch.size",
    "max_in_flight_requests_per_connection": "max.in.flight",
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


def dump(cls, label, keys):
    print(f"\n--- {label} ---")
    try:
        sig = inspect.signature(cls.__init__)
    except (ValueError, TypeError) as e:
        print(f"  取签名失败: {type(e).__name__}: {e}")
        return {}
    got = {}
    for k in keys:
        if k in sig.parameters:
            d = sig.parameters[k].default
            got[k] = d
            print(f"  {STD.get(k, k):<42} = {d!r}")
        else:
            print(f"  {STD.get(k, k):<42} = （该库无此参数）")
    return got


print("=" * 78)
print("三库 Producer 默认值对照（inspect.signature）")
print("=" * 78)
PKEYS = ["acks", "enable_idempotence", "compression_type",
         "linger_ms", "batch_size",
         "max_in_flight_requests_per_connection", "retries"]
kp_p = dump(KafkaProducer, "kafka-python · KafkaProducer", PKEYS)
cf_p = dump(CfProducer, "confluent-kafka · Producer", PKEYS)
ak_p = dump(AIOKafkaProducer, "aiokafka · AIOKafkaProducer", PKEYS)

print()
print("=" * 78)
print("三库 Consumer 默认值对照（inspect.signature）")
print("=" * 78)
CKEYS = ["auto_offset_reset", "enable_auto_commit",
         "auto_commit_interval_ms", "max_poll_records",
         "session_timeout_ms", "heartbeat_interval_ms",
         "group_id", "isolation_level"]
kp_c = dump(KafkaConsumer, "kafka-python · KafkaConsumer", CKEYS)
cf_c = dump(CfConsumer, "confluent-kafka · Consumer", CKEYS)
ak_c = dump(AIOKafkaConsumer, "aiokafka · AIOKafkaConsumer", CKEYS)

print()
print("=" * 78)
print("差异汇总：三库默认值不一致的项（换库时行为会变）")
print("=" * 78)
diff_rows = []
for key, std in STD.items():
    vals = {}
    for name, d in [("kafka-python", {**kp_p, **kp_c}),
                    ("confluent", {**cf_p, **cf_c}),
                    ("aiokafka", {**ak_p, **ak_c})]:
        if key in d:
            vals[name] = d[key]
    if len(vals) >= 2:
        uniq = set(map(repr, vals.values()))
        if len(uniq) > 1:
            diff_rows.append((std, vals))

if diff_rows:
    for std, vals in diff_rows:
        print(f"\n  {std}:")
        for lib, v in vals.items():
            print(f"    {lib:<15} = {v!r}")
else:
    print("  （三库默认值一致，无差异）")

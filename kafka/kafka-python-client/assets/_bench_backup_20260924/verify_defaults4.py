"""课 2：配置项默认值核验 v4 —— 每个库用「它真正支持的入口」。

前面三版踩的坑（全是本课素材）：
  v1: confluent Producer 无 .conf 属性；kafka.producer.kafka 无 DEFAULT_CONFIG
  v2: kafka.consumer.kafka 模块不存在（正确是 kafka.consumer.group）
  v3: kafka-python / confluent 用 **kwargs 收配置，inspect.signature 查不到

最终方法论（按库分入口）：
  - kafka-python：DEFAULT_CONFIG 在 kafka/producer/kafka.py 与 kafka/consumer/group.py
                  名字可能不同 → 先探测模块级 dict
  - confluent   ：配置项不进签名、也不暴露实例属性
                  → 只能「构造后不报错」证明合法，默认值看 librdkafka 文档
                  → 但可用「传非法值看报错」反推支持哪些 key
  - aiokafka    ：显式签名参数 → inspect.signature 直接读
"""
import importlib
import inspect

# ============ kafka-python：探测模块级默认配置 dict ============
print("=" * 78)
print("kafka-python：探测模块级 DEFAULT_CONFIG")
print("=" * 78)


def find_default_config(modname, probe_key):
    """在模块里找含 probe_key 的 dict（不猜名字）。"""
    mod = importlib.import_module(modname)
    for name in dir(mod):
        if name.startswith("_"):
            continue
        obj = getattr(mod, name)
        if isinstance(obj, dict) and probe_key in obj:
            return name, obj
    return None, None


for modname, probe, label in [
    ("kafka.producer.kafka", "acks", "KafkaProducer"),
    ("kafka.consumer.group", "auto_offset_reset", "KafkaConsumer"),
]:
    name, cfg = find_default_config(modname, probe)
    print(f"\n--- {label}（模块 {modname}）---")
    if not cfg:
        print("  未找到（该模块无模块级默认 dict）")
        continue
    print(f"  默认配置对象名: {name}（{len(cfg)} 项）")
    KEYS = {
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
    for pyk, stdk in KEYS.items():
        if pyk in cfg:
            print(f"    {stdk:<42} = {cfg[pyk]!r}")

# ============ confluent：用「非法值报错」反推支持的 key ============
print("\n" + "=" * 78)
print("confluent-kafka：配置项不进签名，用「非法值报错」反推")
print("=" * 78)
from confluent_kafka import Consumer, Producer
from confluent_kafka import KafkaException

print("  方法：传一个明显非法的值，若报 'No such configuration property'")
print("        说明 key 名写错；若报别的错，说明 key 合法。\n")

TEST_KEYS = ["acks", "enable.idempotence", "auto.offset.reset",
             "enable.auto.commit", "max.poll.records",
             "session.timeout.ms", "heartbeat.interval.ms",
             "compression.type", "linger.ms", "batch.size",
             "isolation.level", "max.in.flight.requests.per.connection"]

for cls, label in [(Producer, "Producer"), (Consumer, "Consumer")]:
    print(f"  --- {label} ---")
    for k in TEST_KEYS:
        base = {"bootstrap.servers": "kafka-1:9092"}
        if cls is Consumer:
            base["group.id"] = "probe"
        base[k] = "__INVALID_VALUE_FOR_PROBE__"
        try:
            cls(base)
            print(f"    {k:<42} ✓ 合法（构造未报错）")
        except KafkaException as e:
            msg = str(e)
            if "No such configuration property" in msg:
                print(f"    {k:<42} ✗ key 不被识别")
            else:
                print(f"    {k:<42} ✓ 合法（值非法但 key 存在）")
        except Exception as e:
            print(f"    {k:<42} ? {type(e).__name__}: {str(e)[:50]}")

# ============ aiokafka：签名直读 ============
print("\n" + "=" * 78)
print("aiokafka：显式签名参数，inspect.signature 直读")
print("=" * 78)
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

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
    print(f"\n  --- {label} ---")
    sig = inspect.signature(cls.__init__)
    for k in keys:
        if k in sig.parameters:
            d = sig.parameters[k].default
            d = "（无默认，必填）" if d is inspect.Parameter.empty else repr(d)
            print(f"    {k:<42} = {d}")

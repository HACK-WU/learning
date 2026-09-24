"""课 2：配置项默认值核验方法 v2（上一版两处 API 猜错，这版先探结构）。

v1 的两个错：
  1. confluent 的 Producer 没有 .conf 属性（AttributeError）
  2. kafka-python 没有 DEFAULT_CONFIG（ImportError）

正确方法：先用 dir()/inspect 探明对象结构，再取值。
"""
import inspect

# ================= 1. confluent-kafka =================
print("=" * 70)
print("1. confluent-kafka：先探 Producer 有什么")
print("=" * 70)
from confluent_kafka import Consumer, Producer

p = Producer({"bootstrap.servers": "kafka-1:9092"})
attrs = [a for a in dir(p) if not a.startswith("_")]
print(f"  公开属性/方法: {attrs}")

print("\n  → 真实读法：把配置 dict 原样传进去，用 list_topics 等触发？不。")
print("     正确方式：confluent 提供 Producer.conf 是方法还是属性？")
try:
    r = p.conf
    print(f"  type(p.conf) = {type(r).__name__}")
    if callable(r):
        print(f"  是方法 → 调用结果: {r()}")
        conf = r()
        for k in ["acks", "enable.idempotence", "compression.type",
                  "linger.ms", "batch.size",
                  "max.in.flight.requests.per.connection", "retries"]:
            print(f"    {k:<45} = {conf.get(k, '（无）')!r}")
except AttributeError as e:
    print(f"  失败: {e}")
    # 兜底：查类定义
    print("  改用 inspect 看 Producer 的类属性")

print("\n--- Consumer 同理 ---")
c = Consumer({"bootstrap.servers": "kafka-1:9092", "group.id": "probe"})
try:
    conf2 = c.conf() if callable(getattr(c, "conf", None)) else None
    if conf2:
        for k in ["auto.offset.reset", "enable.auto.commit",
                  "auto.commit.interval.ms", "max.poll.records",
                  "session.timeout.ms", "heartbeat.interval.ms",
                  "isolation.level"]:
            print(f"    {k:<45} = {conf2.get(k, '（无）')!r}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {e}")

# ================= 2. kafka-python =================
print("\n" + "=" * 70)
print("2. kafka-python：默认值在哪")
print("=" * 70)
import kafka.producer.kafka as pk
import kafka.consumer.kafka as ck

print("  kafka.producer.kafka 里含 CONFIG 的名字:")
names = [n for n in dir(pk) if "CONFIG" in n.upper()]
print(f"    {names}")

for mod, label in [(pk, "Producer"), (ck, "Consumer")]:
    print(f"\n  --- {label} ---")
    found = None
    for n in dir(mod):
        if "DEFAULT" in n.upper() and "CONFIG" in n.upper():
            found = n
            break
    if not found:
        # 退而求其次：找模块级 dict
        for n in dir(mod):
            obj = getattr(mod, n)
            if isinstance(obj, dict) and "bootstrap_servers" in obj:
                found = n
                break
    if found:
        cfg = getattr(mod, found)
        print(f"    找到: {found}（{len(cfg)} 项）")
        keys = {
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
        for pyk, stdk in keys.items():
            if pyk in cfg:
                print(f"      {stdk:<42} = {cfg[pyk]!r}")
    else:
        print("    未找到 DEFAULT_CONFIG 类对象，改用 signature")

# ================= 3. aiokafka =================
print("\n" + "=" * 70)
print("3. aiokafka：inspect.signature 读默认值")
print("=" * 70)
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

for cls, label, keys in [
    (AIOKafkaProducer, "AIOKafkaProducer",
     ["acks", "enable_idempotence", "compression_type",
      "linger_ms", "batch_size", "max_batch_size"]),
    (AIOKafkaConsumer, "AIOKafkaConsumer",
     ["auto_offset_reset", "enable_auto_commit",
      "auto_commit_interval_ms", "max_poll_records",
      "session_timeout_ms", "heartbeat_interval_ms",
      "group_id", "isolation_level"]),
]:
    print(f"\n  --- {label} ---")
    sig = inspect.signature(cls.__init__)
    for k in keys:
        if k in sig.parameters:
            print(f"    {k:<42} = {sig.parameters[k].default!r}")

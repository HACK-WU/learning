"""课 2 核心实测：三库 Producer/Consumer API 存在性对照。

不凭记忆写对照表 —— 直接用 hasattr 实测每个方法在不在。
重点回答：换库时哪些 API 会静默崩（AttributeError）。
"""

# Producer 侧常见方法（含 Java 命名，用于验证"陷阱"）
PRODUCER_APIS = [
    # (展示名, 是否 Java 风格)
    "send", "flush", "close", "partitions_for",
    "commit_transaction", "begin_transaction", "abort_transaction",
    "init_transactions",
    "send_offsets_to_transaction",
    "purge",
]

# Consumer 侧常见方法（含 Java 命名陷阱）
CONSUMER_APIS = [
    "subscribe", "assign", "poll", "commit", "close",
    "commitSync",          # ← Java 命名，主教程踩过的坑
    "commitAsync",         # ← Java 命名
    "seek", "seek_to_beginning", "seek_to_end",
    "position", "committed", "beginning_offsets", "end_offsets",
    "unsubscribe", "pause", "resume",
    "topics", "partitions_for_topic",
    "assignment", "subscription",
]


def probe(obj, apis, label):
    print(f"--- {label} ---")
    present, absent = [], []
    for a in apis:
        if hasattr(obj, a):
            present.append(a)
        else:
            absent.append(a)
    print(f"  存在 ({len(present)}): {', '.join(present)}")
    print(f"  缺失 ({len(absent)}): {', '.join(absent) if absent else '（无）'}")
    return set(present)


results = {}

print("=" * 70)
print("1. kafka-python (3.0.11)")
print("=" * 70)
try:
    from kafka import KafkaConsumer, KafkaProducer

    print(f"  KafkaProducer 存在: {hasattr(KafkaProducer, '__init__')}")
    results["kafka-python-producer"] = probe(KafkaProducer, PRODUCER_APIS, "KafkaProducer")
    results["kafka-python-consumer"] = probe(KafkaConsumer, CONSUMER_APIS, "KafkaConsumer")
except Exception as e:
    print(f"  导入失败: {type(e).__name__}: {e}")

print()
print("=" * 70)
print("2. confluent-kafka (2.15.1)")
print("=" * 70)
try:
    import confluent_kafka

    print(f"  版本: {confluent_kafka.version()}")
    print(f"  librdkafka: {confluent_kafka.libversion()}")
    from confluent_kafka import Consumer, Producer

    results["confluent-producer"] = probe(Producer, PRODUCER_APIS, "Producer")
    results["confluent-consumer"] = probe(Consumer, CONSUMER_APIS, "Consumer")
except Exception as e:
    print(f"  导入失败: {type(e).__name__}: {e}")

print()
print("=" * 70)
print("3. aiokafka (0.14.0)")
print("=" * 70)
try:
    from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

    results["aiokafka-producer"] = probe(AIOKafkaProducer, PRODUCER_APIS, "AIOKafkaProducer")
    results["aiokafka-consumer"] = probe(AIOKafkaConsumer, CONSUMER_APIS, "AIOKafkaConsumer")
except Exception as e:
    print(f"  导入失败: {type(e).__name__}: {e}")

print()
print("=" * 70)
print("交叉对比：Consumer 侧 API 差异")
print("=" * 70)
kp = results.get("kafka-python-consumer", set())
cf = results.get("confluent-consumer", set())
ak = results.get("aiokafka-consumer", set())

allc = kp | cf | ak
print(f"{'API':<28}{'kafka-python':<16}{'confluent':<14}{'aiokafka'}")
print("-" * 70)
for a in sorted(CONSUMER_APIS):
    def mark(s):
        return "✓" if a in s else "✗"
    row = f"{a:<28}{mark(kp):<16}{mark(cf):<14}{mark(ak)}"
    print(row)
    # 高亮：只在部分库存在 → 换库会崩
    cnt = sum(a in s for s in (kp, cf, ak))
    if 0 < cnt < 3:
        print(f"{'':<28}↑ 仅 {cnt}/3 库有 → 换库时静默崩风险")

"""课 2：列出三库真实的公开方法面，找出「换库时该用什么替代」。

上一版只测了"我猜的 API 在不在"。这版反过来：
把每个类的真实公开方法列出来，建立映射关系。
"""

import inspect

TARGETS = [
    ("kafka-python", "KafkaProducer", "from kafka import KafkaProducer as C"),
    ("kafka-python", "KafkaConsumer", "from kafka import KafkaConsumer as C"),
    ("confluent-kafka", "Producer", "from confluent_kafka import Producer as C"),
    ("confluent-kafka", "Consumer", "from confluent_kafka import Consumer as C"),
    ("aiokafka", "AIOKafkaProducer", "from aiokafka import AIOKafkaProducer as C"),
    ("aiokafka", "AIOKafkaConsumer", "from aiokafka import AIOKafkaConsumer as C"),
]


def public_methods(cls):
    out = set()
    for name, _ in inspect.getmembers(cls, predicate=callable):
        if name.startswith("_"):
            continue
        out.add(name)
    # 协程方法在类上也是 function，getmembers 能拿到
    return out


store = {}
for lib, cname, imp in TARGETS:
    ns = {}
    try:
        exec(imp, ns)
        cls = ns["C"]
        ms = public_methods(cls)
        store[(lib, cname)] = ms
        print(f"=== {lib} · {cname} （{len(ms)} 个公开方法）===")
        print("  " + ", ".join(sorted(ms)))
        print()
    except Exception as e:
        print(f"=== {lib} · {cname} 导入失败: {type(e).__name__}: {e}")
        print()

print("=" * 70)
print("关键：confluent 的「缺失方法」到底该怎么替代")
print("=" * 70)
cf_c = store.get(("confluent-kafka", "Consumer"), set())
cf_p = store.get(("confluent-kafka", "Producer"), set())
kp_c = store.get(("kafka-python", "KafkaConsumer"), set())
kp_p = store.get(("kafka-python", "KafkaProducer"), set())
ak_c = store.get(("aiokafka", "AIOKafkaConsumer"), set())

print()
print("--- confluent Consumer 里「看起来没有但其实是别的名字」的 ---")
for m in ["seek_to_beginning", "seek_to_end", "topics", "partitions_for_topic",
          "beginning_offsets", "end_offsets", "subscription"]:
    if m not in cf_c:
        # 找候选：包含关键词的
        cands = sorted(x for x in cf_c
                       if any(k in x for k in ("watermark", "offset", "list_topics",
                                               "subscribe", "memberid", "assignment")))
        print(f"  {m:<24} 不存在 → 候选替代: {cands if cands else '（无，需另想办法）'}")

print()
print("--- confluent Producer 的发送方法 ---")
send_like = sorted(x for x in cf_p if any(k in x for k in ("prod", "send", "write")))
print(f"  发送相关: {send_like}")
print(f"  是否有 send: {'send' in cf_p}   是否有 produce: {'produce' in cf_p}")

print()
print("--- aiokafka Consumer 的生命周期方法 ---")
life = sorted(x for x in ak_c if any(k in x for k in ("start", "stop", "close", "exit", "enter")))
print(f"  生命周期: {life}")
print(f"  是否有 close: {'close' in ak_c}   是否有 stop: {'stop' in ak_c}")

print()
print("--- aiokafka Consumer 的拉取方法（替代 poll）---")
pull = sorted(x for x in ak_c if any(k in x for k in ("get", "poll", "__aiter", "fetch")))
print(f"  拉取相关: {pull}")

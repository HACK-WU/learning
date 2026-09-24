"""查消费组状态（在容器内跑，不调 docker）。
重点：
  1. 组里有几个成员 / 怎么分配的
  2. topic 实际分区数
  3. poll 5 秒延迟的原因（max.poll.interval? rebalance?）
"""
import json
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.kafka_client import build_consumer  # noqa: E402

print("=" * 74)
print("课13 · 消费组状态诊断")
print("=" * 74)

from confluent_kafka.admin import AdminClient  # noqa: E402

a = AdminClient({"bootstrap.servers": config.BROKERS})

md = a.list_topics(timeout=10)
t = md.topics.get(config.TOPIC_ORDERS)
print(f"\n  topic {config.TOPIC_ORDERS}: 分区数 = {len(t.partitions) if t else 'N/A'}")
t2 = md.topics.get(config.TOPIC_DLQ)
print(f"  topic {config.TOPIC_DLQ}: 分区数 = {len(t2.partitions) if t2 else 'N/A'}")

# 起一个独立消费者看能分到几个分区（用不同 group 才能看全貌）
gid2 = f"{config.GROUP_ID}-probe-{int(time.time()) % 10000}"
c = build_consumer()
from confluent_kafka import Consumer  # noqa: E402
c2 = Consumer({"bootstrap.servers": config.BROKERS, "group.id": gid2,
               "auto.offset.reset": "earliest", "enable.auto.commit": False,
               "session.timeout.ms": 45000, "statistics.interval.ms": 1000})
stats = []
c2.subscribe([config.TOPIC_ORDERS])
print(f"\n  探针组 {gid2} 订阅中…")
t0 = time.time()
while time.time() - t0 < 25:
    c2.poll(1.0)
    if len(c2.assignment()) == 4:
        break
print(f"  探针分到 {len(c2.assignment())} 个分区（等了 {time.time()-t0:.1f}s）")
print(f"  -> 若探针能拿 4 个，说明原组 {config.GROUP_ID} 里有【其他成员】占着")
c2.close()

# 检查原组：用一个同组消费者看 rebalance 情况
print(f"\n  检查原组 {config.GROUP_ID} 成员…")
c3 = Consumer({"bootstrap.servers": config.BROKERS, "group.id": config.GROUP_ID,
               "auto.offset.reset": "earliest", "enable.auto.commit": False,
               "session.timeout.ms": 45000, "statistics.interval.ms": 1000})
st = []
c3.subscribe([config.TOPIC_ORDERS])
t0 = time.time()
while time.time() - t0 < 20:
    c3.poll(1.0)
    if c3.assignment():
        break
print(f"  同组成员分到 {len(c3.assignment())} 个分区")
print("  -> 同组新成员加入会触发 rebalance，此刻分配的分区数反映组内成员数")
c3.close()

# poll 延迟精测：单独测一次 poll 耗时
print(f"\n  poll 延迟精测（空 topic 场景 vs 有消息场景）")
c4 = build_consumer()
c4.subscribe([config.TOPIC_ORDERS])
for _ in range(10):
    c4.poll(1.0)
    if c4.assignment():
        break
print(f"    分到 {len(c4.assignment())} 分区")
lat = []
for i in range(10):
    t0 = time.time()
    m = c4.poll(timeout=1.0)
    lat.append((time.time() - t0) * 1000)
    if m and not m.error():
        pass
print(f"    poll 耗时(ms): {[round(x) for x in lat]}")
print(f"    中位 = {sorted(lat)[len(lat)//2]:.0f}ms")
c4.close()

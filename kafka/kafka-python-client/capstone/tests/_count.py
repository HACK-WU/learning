"""验证"永远差一条"假设：
  三轮都是 1999/2000，且耗时整 60s（超时上限）
  假设：1999 条瞬间消费完，然后卡在等第 2000 条
  验证：查 topic 的 watermark（真实消息数）
"""
import json
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from confluent_kafka import Consumer, Producer  # noqa: E402
from confluent_kafka.admin import AdminClient, NewTopic  # noqa: E402

a = AdminClient({"bootstrap.servers": config.BROKERS})
N = 2000
topic = f"count-{int(time.time()) % 100000}"
for t, f in a.create_topics([NewTopic(topic, num_partitions=4,
                                      replication_factor=1)]).items():
    f.result()

pp = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
for i in range(N):
    pp.produce(topic, json.dumps({"i": i}).encode())
remain = pp.flush(15)
print(f"  produce {N} 条，flush 后剩余 {remain}")

# 查每分区 watermark
c = Consumer({"bootstrap.servers": config.BROKERS,
              "group.id": f"cnt-{int(time.time()) % 100000}",
              "auto.offset.reset": "earliest", "enable.auto.commit": False})
c.subscribe([topic])
for _ in range(20):
    c.poll(1.0)
    if len(c.assignment()) == 4:
        break
total = 0
print(f"\n  分区水位（真实消息数）:")
for tp in sorted(c.assignment(), key=lambda x: x.partition):
    lo, hi = c.get_watermark_offsets(tp, timeout=5)
    total += hi
    print(f"    分区{tp.partition}: lo={lo} hi={hi}  ({hi-lo} 条)")
print(f"  合计 = {total} 条（期望 {N}）")

# 消费并精确计时：记录每条的到达时间
print(f"\n  消费并计时（记录前 20 条与最后 5 条）")
n = 0
t0 = time.time()
arrivals = []
while n < N and time.time() - t0 < 45:
    m = c.poll(timeout=1.0)
    if m is None or m.error():
        continue
    n += 1
    arrivals.append(time.time() - t0)
el = time.time() - t0

if arrivals:
    print(f"    消费 {n} 条 / {el:.2f}s")
    print(f"    前 10 条耗时: {[round(x*1000,1) for x in arrivals[:10]]} ms")
    print(f"    第 {len(arrivals)-1} 条到达于 {arrivals[-1]:.2f}s")
    # 计算"消费完 95% 用时"
    if len(arrivals) >= 20:
        t95 = arrivals[int(len(arrivals) * 0.95) - 1]
        print(f"\n    95% 消息到达用时 = {t95:.3f}s -> 速率 = {int(len(arrivals)*0.95)/t95:.0f} 条/秒")
        print(f"    最后一条到达用时 = {arrivals[-1]:.3f}s")
        if arrivals[-1] - t95 > 5:
            print(f"\n  >> 验证成立：绝大多数消息在 {t95:.2f}s 内到达，")
            print(f"     最后几条等了 {arrivals[-1]-t95:.1f}s -> 之前的'低速率'是尾部等待造成的假象")
c.close()

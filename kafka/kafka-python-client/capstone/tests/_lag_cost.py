"""直接测 collect_lag 单次耗时 —— 验证它是不是真正的瓶颈。
假设：4 分区 × (get_watermark_offsets + committed) 两个网络往返，
      单次可能高达数秒；120 秒内节流触发 24 次就把消费时间占满。
对照实验 C 组没发现，是因为它 0.00s 就消费完 300 条，根本没触发 lag 采集。
"""
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.kafka_client import build_consumer, collect_lag  # noqa: E402
from confluent_kafka import Consumer  # noqa: E402

print("=" * 74)
print("课13 · collect_lag 单次耗时实测")
print("=" * 74)

c = Consumer({"bootstrap.servers": config.BROKERS,
              "group.id": f"lagtime-{int(time.time())%100000}",
              "auto.offset.reset": "earliest", "enable.auto.commit": False})
c.subscribe([config.TOPIC_ORDERS])
for _ in range(20):
    c.poll(1.0)
    if c.assignment():
        break
print(f"\n  分到 {len(c.assignment())} 个分区")

times = []
print("\n  连续测 10 次 collect_lag:")
for i in range(10):
    t0 = time.time()
    r = collect_lag(c, config.TOPIC_ORDERS)
    el = (time.time() - t0) * 1000
    times.append(el)
    print(f"    [{i+1:2d}] {el:>8.1f}ms  分区数={len(r)}")

times.sort()
med = times[len(times) // 2]
print(f"\n  中位 = {med:.1f}ms   最大 = {times[-1]:.1f}ms")

# 分开测两个操作各自耗时
print("\n  拆解：get_watermark_offsets vs committed")
tps = list(c.assignment())
tw = tc = 0.0
for tp in tps:
    t0 = time.time(); c.get_watermark_offsets(tp, timeout=3); tw += time.time() - t0
    t0 = time.time(); c.committed([tp], timeout=3); tc += time.time() - t0
print(f"    get_watermark_offsets 合计 {tw*1000:.1f}ms（{len(tps)} 分区）")
print(f"    committed            合计 {tc*1000:.1f}ms（{len(tps)} 分区）")

# 影响估算
print(f"\n  影响估算：")
for interval in (1, 5, 30):
    n = 120 // interval
    cost = n * med / 1000
    print(f"    节流 {interval:>2}s -> 120s 内触发 {n:>3} 次，累计占用 {cost:>6.1f}s "
          f"({cost/120*100:>4.1f}%)")
c.close()

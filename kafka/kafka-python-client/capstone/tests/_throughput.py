"""权威吞吐测量：3 轮取中位，每轮独立 group + 独立 topic。
排除两个干扰源：
  1. 同组 rebalance（用独立 group.id）
  2. 同容器 CPU 竞争（由外部脚本先停掉服务）
"""
import json
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.schema import OrderEvent  # noqa: E402
from app.worker import default_process  # noqa: E402
from confluent_kafka import Consumer, Producer  # noqa: E402
from confluent_kafka.admin import AdminClient, NewTopic  # noqa: E402

N = 2000
ROUNDS = 3
a = AdminClient({"bootstrap.servers": config.BROKERS})
rates = []

print("=" * 74)
print("课13 · 权威吞吐测量（3 轮取中位）")
print("=" * 74)

for r in range(ROUNDS):
    topic = f"tp-{r}-{int(time.time()) % 10000}"
    if topic not in a.list_topics(timeout=10).topics:
        for t, f in a.create_topics([NewTopic(topic, num_partitions=4,
                                              replication_factor=1)]).items():
            f.result()
    pp = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
    for i in range(N):
        pp.produce(topic, json.dumps({"order_id": f"t{i:05d}", "user_id": "u",
                                      "amount": 10.0 + i, "currency": "CNY"}).encode())
    pp.flush(15)

    gid = f"tp-{r}-{int(time.time()) % 100000}"
    conf = dict(config.consumer_conf()); conf["group.id"] = gid
    c = Consumer(conf)
    c.subscribe([topic])
    for _ in range(20):
        c.poll(1.0)
        if len(c.assignment()) == 4:
            break
    n = 0
    t0 = time.time()
    while n < N and time.time() - t0 < 60:
        m = c.poll(timeout=1.0)
        if m is None or m.error():
            continue
        n += 1
        try:
            default_process(OrderEvent.from_json(m.value()))
        except Exception:
            pass
        c.commit(message=m, asynchronous=True)
    el = time.time() - t0
    rate = n / el if el > 0 else 0
    rates.append(rate)
    print(f"  轮{r+1}: {n}/{N} 条 / {el:.2f}s = {rate:>10.0f} 条/秒")
    c.close()

rates.sort()
med = rates[len(rates) // 2]
print(f"\n  中位吞吐 = {med:.0f} 条/秒")
print(f"  三轮: {[round(x) for x in rates]}")
print(f"\n  对比：")
print(f"    Kong 基准（纯 poll+解析，无 commit）: 237688 条/秒")
print(f"    本测量（含 from_json + process + 异步 commit）: {med:.0f} 条/秒")

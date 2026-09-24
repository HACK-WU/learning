"""分段计时：复现服务 worker 的完整配置，逐环节测耗时。
前几轮每次"修复"都变慢（16.6->11.1->3.8/s），说明诊断方向错了。
这次不猜，直接测每个环节。
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

print("=" * 74)
print("课13 · 服务 worker 完整配置分段计时")
print("=" * 74)

N = 500
TOPIC = "capstone-seg"
a = AdminClient({"bootstrap.servers": config.BROKERS})
if TOPIC not in set(a.list_topics(timeout=10).topics):
    for t, f in a.create_topics([NewTopic(TOPIC, num_partitions=4, replication_factor=1)]).items():
        f.result()

p = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
for i in range(N):
    p.produce(TOPIC, json.dumps({"order_id": f"s{i:05d}", "user_id": "u",
                                 "amount": 10.0 + i, "currency": "CNY"}).encode())
p.flush(15)
print(f"\n  预灌 {N} 条\n")

# 完全复刻 config.consumer_conf()
c = Consumer(config.consumer_conf())
c.subscribe([TOPIC])
for _ in range(20):
    c.poll(1.0)
    if len(c.assignment()) == 4:
        break
print(f"  分到 {len(c.assignment())} 分区")
print(f"  配置: { {k: v for k, v in config.consumer_conf().items() if k in ('max.poll.records','session.timeout.ms','enable.auto.commit')} }")

t_poll = t_parse = t_commit = 0.0
n = 0
poll_calls = 0
slow_polls = []
t0 = time.time()
while n < N and time.time() - t0 < 90:
    ts = time.time()
    msg = c.poll(timeout=1.0)
    el = time.time() - ts
    t_poll += el
    poll_calls += 1
    if el > 0.05:
        slow_polls.append(round(el * 1000))
    if msg is None or msg.error():
        continue
    n += 1
    ts = time.time()
    try:
        default_process(OrderEvent.from_json(msg.value()))
    except Exception:
        pass
    t_parse += time.time() - ts
    ts = time.time()
    c.commit(message=msg, asynchronous=True)
    t_commit += time.time() - ts

el = time.time() - t0
print(f"\n  {'环节':<16}{'总耗时':>12}{'每条约':>12}")
print(f"  {'-'*40}")
for name, tot in (("poll", t_poll), ("解析+处理", t_parse), ("异步commit", t_commit)):
    print(f"  {name:<14}{tot:>11.3f}s{tot/max(n,1)*1000:>11.3f}ms")
print(f"  {'-'*40}")
print(f"  {'墙钟':<14}{el:>11.3f}s{el/max(n,1)*1000:>11.3f}ms")
print(f"\n  消费 {n} 条 / {el:.2f}s = {n/el:.1f} 条/秒")
print(f"  poll 调用 {poll_calls} 次，其中 >50ms 的 {len(slow_polls)} 次")
if slow_polls:
    print(f"  慢 poll 样本(ms): {slow_polls[:15]}")
other = el - t_poll - t_parse - t_commit
print(f"\n  未归类耗时 = {other:.2f}s ({other/el*100:.1f}%)")
if other / el > 0.3:
    print("  >> 有显著时间在三个环节之外 —— 可能在 poll 的阻塞等待里")
c.close()

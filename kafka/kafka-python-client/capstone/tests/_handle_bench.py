"""决定性实验：把 OrderWorker 的 _handle 完整逻辑搬到独立进程。
排除"服务环境"变量，只测代码逻辑本身。

  裸循环（已测）        : 74233 条/秒
  服务进程（已测）      :     8 条/秒
  -> 本实验在中间：用 worker 的真实 _handle/_commit 路径
"""
import json
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config, metrics  # noqa: E402
from app.schema import OrderEvent, ValidationError  # noqa: E402
from app.worker import default_process  # noqa: E402
from confluent_kafka import Consumer, Producer  # noqa: E402
from confluent_kafka.admin import AdminClient, NewTopic  # noqa: E402

print("=" * 74)
print("课13 · _handle 完整逻辑独立进程测速")
print("=" * 74)

N = 1000
TOPIC = "capstone-handle"
a = AdminClient({"bootstrap.servers": config.BROKERS})
if TOPIC not in a.list_topics(timeout=10).topics:
    for t, f in a.create_topics([NewTopic(TOPIC, num_partitions=4, replication_factor=1)]).items():
        f.result()

p = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
for i in range(N):
    p.produce(TOPIC, json.dumps({"order_id": f"h{i:05d}", "user_id": "u",
                                 "amount": 10.0 + i, "currency": "CNY"}).encode())
p.flush(15)
print(f"\n  预灌 {N} 条")

c = Consumer(config.consumer_conf())


class FakeW:
    """复刻 worker._handle 所需的最小状态。"""
    def __init__(self):
        self.stats = type("S", (), {"ok": 0, "committed": 0})()
        self._c = c
        self._p = None


w = FakeW()


def handle(msg):
    """**逐行复刻** app/worker.py OrderWorker._handle"""
    raw = msg.value()
    try:
        order = OrderEvent.from_json(raw)
    except ValidationError:
        return
    try:
        default_process(order)
    except Exception:
        return
    w.stats.ok += 1
    metrics.CONSUMED.inc(1, result="ok")
    # _commit
    c.commit(message=msg, asynchronous=True)
    w.stats.committed += 1


c.subscribe([TOPIC])
for _ in range(20):
    c.poll(1.0)
    if len(c.assignment()) == 4:
        break
print(f"  分到 {len(c.assignment())} 分区")

n = 0
t0 = time.time()
while n < N and time.time() - t0 < 60:
    msg = c.poll(timeout=1.0)
    if msg is None or msg.error():
        continue
    n += 1
    handle(msg)
el = time.time() - t0
print(f"\n  消费 {n} 条 / {el:.2f}s = {n/el:.1f} 条/秒")

if n / el > 1000:
    print("\n  ✓ _handle 逻辑本身很快 -> 瓶颈在服务进程环境（GIL/uvicorn）")
else:
    print("\n  ✗ _handle 逻辑本身就慢 -> 定位到具体是哪一行")
c.close()

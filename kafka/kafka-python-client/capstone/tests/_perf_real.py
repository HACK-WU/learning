"""重测真实消费速率（修正上轮测量错误）。

上轮错误：
  - 把空 poll 的时间算进分子，消息数当分母 -> 得出 poll 5007ms/条的伪结论
  - 且当时组里有僵尸进程占着分区，实际只消费 2 个分区

正确测法：
  1. 先确认独占 4 个分区
  2. 灌 N 条消息，测"从第一条到最后一条"的墙钟时间
  3. 速率 = N / 耗时
"""
import json
import sys
import time
import urllib.request

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.kafka_client import OrderProducer  # noqa: E402

BASE = "http://localhost:8000"


def stats():
    with urllib.request.urlopen(BASE + "/stats", timeout=20) as r:
        return json.loads(r.read().decode())


print("=" * 74)
print("课13 · 真实消费速率重测")
print("=" * 74)

s = stats()
print(f"\n  当前分区 lag: {s['lag_by_partition']}  合计={s['lag_total']}")
print(f"  覆盖分区数 = {len(s['lag_by_partition'])}（应为 4）")

if len(s["lag_by_partition"]) < 4:
    print("  ⚠ 未独占 4 分区，组内可能仍有其他成员")

# 等积压排空，确保测的是"新消息的处理速度"
print("\n  等待积压排空…")
for i in range(120):
    s = stats()
    if s["lag_total"] <= 1:
        break
    if i % 15 == 0:
        print(f"    [{i}s] lag={s['lag_total']}")
    time.sleep(1)
print(f"    排空完成 lag={stats()['lag_total']}")

# 灌 N 条，测处理耗时
N = 2000
print(f"\n  灌 {N} 条消息，测处理耗时…")
p = OrderProducer(); p.start()
t0 = time.time()
for i in range(N):
    p.produce(f"perf-{i:05d}",
              json.dumps({"order_id": f"perf-{i:05d}", "user_id": f"u{i%100}",
                          "amount": 10.0 + i, "currency": "CNY"}).encode())
p.flush(15)
prod_elapsed = time.time() - t0
print(f"    生产耗时 {prod_elapsed:.2f}s -> 生产速率 {N/prod_elapsed:.0f} 条/秒")

# 等消费完
base_ok = stats()["consumed_ok"]
t0 = time.time()
target = base_ok + N
while time.time() - t0 < 120:
    cur = stats()["consumed_ok"]
    if cur >= target:
        break
    time.sleep(0.5)
consume_elapsed = time.time() - t0
cur = stats()["consumed_ok"]
got = cur - base_ok
rate = got / consume_elapsed if consume_elapsed > 0 else 0

print(f"\n  消费 {got} 条耗时 {consume_elapsed:.2f}s")
print(f"  >> 消费速率 = {rate:.1f} 条/秒")
print(f"  >> 最终 lag = {stats()['lag_total']}")

if rate > 200:
    print(f"\n  ✓ 消费性能正常（>200 条/秒），此前 0.7 条/秒 是测量错误")
elif rate > 20:
    print(f"\n  ~ 速率 {rate:.0f}/s，对单线程 Python 合理（受同步 commit 限制）")
else:
    print(f"\n  ✗ 仍慢（{rate:.1f}/s），需继续排查")
p.close()

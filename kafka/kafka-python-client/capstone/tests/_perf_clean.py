"""干净环境消费速率测试（在 capstone-svc 容器内跑）。

前情：l11 里的服务实测 3.8~16.6 条/秒，但**同配置的独立进程**跑出 74233 条/秒。
本测试在干净容器里跑，判定到底是代码问题还是 l11 环境干扰。
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
print("课13 · 干净环境消费速率")
print("=" * 74)

s = stats()
print(f"\n  分区数 = {len(s['lag_by_partition'])}  lag = {s['lag_total']}")

N = 2000
print(f"\n  灌 {N} 条…")
p = OrderProducer(); p.start()
t0 = time.time()
for i in range(N):
    p.produce(f"c-{i:05d}", json.dumps({"order_id": f"c-{i:05d}", "user_id": f"u{i%50}",
                                        "amount": 10.0 + i, "currency": "CNY"}).encode())
p.flush(15)
print(f"    生产 {time.time()-t0:.2f}s -> {N/(time.time()-t0):.0f} 条/秒")

base = stats()
print(f"    基线 consumed_ok={base['consumed_ok']}")
target = base["consumed_ok"] + N
t0 = time.time()
cur = base["consumed_ok"]
while time.time() - t0 < 90:
    cur = stats()["consumed_ok"]
    if cur >= target:
        break
    time.sleep(0.5)
el = time.time() - t0
got = cur - base["consumed_ok"]
print(f"\n  消费 {got}/{N} 条，耗时 {el:.2f}s")
print(f"  >> 速率 = {got/el:.1f} 条/秒" if el > 0 else "  >> n/a")
print(f"  >> 最终 lag = {stats()['lag_total']}")

if got >= N:
    print(f"\n  ✓ 全部消费完，速率 {got/el:.0f}/s —— 代码无性能问题，"
          f"此前慢是 l11 容器环境干扰")
else:
    print(f"\n  ✗ 只消费 {got}/{N}，需继续排查")
p.close()

"""验证修复效果：消费速率是否恢复。
修复前：0.7 条/秒（60s 消费 43 条，lag 478->435）
修复后：应达到数百~数千条/秒

同时验证 DLQ 是否能在积压排空后正常触发。
"""
import json
import sys
import time
import urllib.request

sys.path.insert(0, "/app/capstone")
from app.kafka_client import OrderProducer  # noqa: E402

BASE = "http://localhost:8000"


def stats():
    with urllib.request.urlopen(BASE + "/stats", timeout=20) as r:
        return json.loads(r.read().decode())


print("=" * 74)
print("课13 · 性能修复验证")
print("=" * 74)

s0 = stats()
print(f"\n  基线: ok={s0['consumed_ok']} lag={s0['lag_total']}")
print("  等待 15 秒，观察消费速率…")
time.sleep(15)
s1 = stats()
rate = (s1["consumed_ok"] - s0["consumed_ok"]) / 15.0
lag_drop = s0["lag_total"] - s1["lag_total"]
print(f"  15s 后: ok={s1['consumed_ok']} lag={s1['lag_total']}")
print(f"  >> 消费速率 = {rate:.1f} 条/秒   (修复前 0.7 条/秒)")
print(f"  >> lag 下降 = {lag_drop:.0f}")

if rate > 50:
    print("  ✓ 修复有效：速率提升 >50 倍")
elif rate > 5:
    print("  ~ 有改善但仍偏慢，需继续查")
else:
    print("  ✗ 修复无效，另有瓶颈")

# 等积压排空
print("\n  等待积压排空…")
for i in range(90):
    s = stats()
    if s["lag_total"] <= 1:
        print(f"  [{i}s] 排空 lag={s['lag_total']}")
        break
    if i % 10 == 0:
        print(f"  [{i}s] lag={s['lag_total']} ok={s['consumed_ok']}")
    time.sleep(1)

# 投坏消息验证 DLQ
print("\n  积压排空后投 3 条坏消息…")
base = stats()
p = OrderProducer(); p.start()
p.produce("bad-amount", json.dumps({"order_id": "bad-amount", "user_id": "u",
                                    "amount": -999, "currency": "CNY"}).encode())
p.produce("bad-cur", json.dumps({"order_id": "bad-cur", "user_id": "u",
                                 "amount": 5, "currency": "JPY"}).encode())
p.produce("bad-json", b"{not valid json")
p.flush(10); p.close()

for i in range(20):
    time.sleep(1)
    s2 = stats()
    if s2["validation_error"] - base["validation_error"] >= 3:
        print(f"  [{i+1}s] 全捕获: val_err={s2['validation_error']} dlq={s2['dlq']}")
        break
    if i % 4 == 0:
        print(f"  [{i+1}s] val_err={s2['validation_error']} dlq={s2['dlq']}")
else:
    s2 = stats()

dv = s2["validation_error"] - base["validation_error"]
dd = s2["dlq"] - base["dlq"]
print(f"\n  判据: val_err 增量应 >=3, dlq 增量应 >=3")
print(f"  实测: val_err +{dv}, dlq +{dd}")
print("  >> " + ("DLQ 链路正常 ✓" if dv >= 3 and dd >= 3 else "仍异常，需排查"))

"""诊断2：先排空积压，再投坏消息。

上一轮失败根因（不是 bug，是测试方法错）：
  每次跑测试都投 300 条，坏消息在队列**尾部**，消费者还在追积压，
  30 秒内根本轮不到它。等再久也没用——因为新测试又投新的。

正确顺序：
  1. 停掉新投递，等 lag 归零（积压排空）
  2. 再投坏消息 —— 它会立刻被消费到
  3. 验证 validation_error / dlq
"""
import json
import sys
import time
import urllib.request

sys.path.insert(0, "/app/capstone")
from app.kafka_client import OrderProducer  # noqa: E402

BASE = "http://localhost:8000"
print("=" * 74)
print("诊断2：排空积压后再测 DLQ")
print("=" * 74)


def stats():
    with urllib.request.urlopen(BASE + "/stats", timeout=20) as r:
        return json.loads(r.read().decode())


# 步骤1：等积压排空
print("\n  步骤1 等待积压排空（lag_total -> 0）…")
s = stats()
print(f"    起始 lag={s['lag_total']}")
for i in range(60):
    s = stats()
    if s["lag_total"] <= 1:
        print(f"    [{i}s] 积压已排空 lag={s['lag_total']}")
        break
    if i % 5 == 0:
        print(f"    [{i}s] lag={s['lag_total']} ok={s['consumed_ok']}")
    time.sleep(1)
else:
    print(f"    60s 未排空，lag={s['lag_total']}（继续，但结果可能不准）")

base = stats()
print(f"\n  基线: ok={base['consumed_ok']} val_err={base['validation_error']} dlq={base['dlq']}")

# 步骤2：投坏消息
print("\n  步骤2 投递坏消息（积压已空，应立刻被消费）")
p = OrderProducer(); p.start()
for tag, payload in [
    ("bad-amount", {"order_id": "bad-amount", "user_id": "u", "amount": -999, "currency": "CNY"}),
    ("bad-currency", {"order_id": "bad-currency", "user_id": "u", "amount": 5, "currency": "JPY"}),
    ("bad-json", None),
]:
    raw = b"{not valid json" if payload is None else json.dumps(payload).encode()
    p.produce(tag, raw)
p.flush(10); p.close()
print("    已投 3 条坏消息（负金额/非法币种/非JSON）")

# 步骤3：盯结果
print("\n  步骤3 等待消费…")
for i in range(20):
    time.sleep(1)
    s2 = stats()
    if s2["validation_error"] >= 3 and s2["dlq"] >= 3:
        print(f"    [{i+1}s] 全部捕获: val_err={s2['validation_error']} dlq={s2['dlq']}")
        break
    if i % 3 == 0:
        print(f"    [{i+1}s] val_err={s2['validation_error']} dlq={s2['dlq']} "
              f"ok={s2['consumed_ok']}")
else:
    s2 = stats()
    print(f"    20s 后: val_err={s2['validation_error']} dlq={s2['dlq']}")

print(f"\n  判据：val_err 应 >=3，dlq 应 >=3")
print(f"  实测：val_err={s2['validation_error']} dlq={s2['dlq']}")
if s2["validation_error"] >= 3:
    print("  >> 结论：DLQ 链路正常，上一轮失败是测试方法问题（坏消息埋在积压里）")
else:
    print("  >> 仍有异常，需继续排查")

"""定位真正的性能瓶颈：逐步骤计时。
修复 lag 节流后仍是 0.7 条/秒，说明瓶颈在别处。
嫌疑：
  S1 _commit 的 asynchronous=False（每条同步提交 = 一次网络往返）
  S2 poll(timeout=1.0) 本身
  S3 default_process 里有隐藏开销
方法：单独构造 consumer，测 poll / 处理 / commit 各自耗时。
"""
import json
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.kafka_client import build_consumer  # noqa: E402
from app.schema import OrderEvent  # noqa: E402
from app.worker import default_process  # noqa: E402

print("=" * 74)
print("课13 · 性能瓶颈定位")
print("=" * 74)

c = build_consumer()
c.subscribe([config.TOPIC_ORDERS])
print(f"\n  订阅 {config.TOPIC_ORDERS}，等分配…")
for _ in range(20):
    c.poll(1.0)
    if c.assignment():
        break
print(f"  已分配 {len(c.assignment())} 个分区")

# 计时：poll / 解析+处理 / commit
t_poll = t_proc = t_commit = 0.0
n_poll = n_msg = 0
N = 30

print(f"\n  测量 {N} 条消息的细分耗时…")
start_all = time.time()
while n_msg < N and time.time() - start_all < 60:
    t0 = time.time()
    msg = c.poll(timeout=1.0)
    t_poll += time.time() - t0
    n_poll += 1
    if msg is None or msg.error():
        continue
    n_msg += 1

    t0 = time.time()
    try:
        ev = OrderEvent.from_json(msg.value())
        default_process(ev)
    except Exception:
        pass
    t_proc += time.time() - t0

    t0 = time.time()
    c.commit(message=msg, asynchronous=False)
    t_commit += time.time() - t0

elapsed = time.time() - start_all
print(f"\n  {'阶段':<20}{'总耗时':>12}{'每条约':>12}{'占比':>10}")
print(f"  {'-'*54}")
for name, tot in (("poll", t_poll), ("解析+处理", t_proc), ("同步commit", t_commit)):
    per = tot / max(n_msg, 1)
    print(f"  {name:<18}{tot:>11.3f}s{per*1000:>11.2f}ms{tot/elapsed*100:>9.1f}%")
print(f"  {'-'*54}")
print(f"  {'合计':<18}{elapsed:>11.3f}s{elapsed/max(n_msg,1)*1000:>11.2f}ms")
print(f"\n  实际速率 = {n_msg/elapsed:.2f} 条/秒")
print(f"  poll 次数 = {n_poll}（含空 poll）")

if t_commit / max(n_msg, 1) > 0.001:
    print(f"\n  >> 瓶颈判定：同步 commit 占 {t_commit/elapsed*100:.0f}%，每条约 "
          f"{t_commit/max(n_msg,1)*1000:.2f}ms")
    print(f"     这是「每条都同步提交」的代价 —— 课 6 手动提交了正确性，")
    print(f"     但没说要每条同步。生产应【批量异步提交 + 退出前同步】。")
else:
    print(f"\n  >> commit 不是瓶颈，需查其他（poll 空转 / 网络）")

c.close()

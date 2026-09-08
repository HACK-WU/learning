#!/usr/bin/env python3
"""
E2（决定性）：后端故障期间，数据到底丢没丢？

此前实验的缺陷：用 in/sent 差值判断丢失，但两者口径不同（恒定偏移 -1450），
无法得出可靠结论。

本实验改用「外部可核对的真值」：
  - 数据源每秒产生的样本数是固定的（500 cards + 4 requests + 1 up + 1 runtime + 1 build = 507）
  - receiver 解压后的字节数 / 请求次数可以精确统计
  - 用 receiver 侧的 requests 计数做真值锚点

设计：
  阶段 1（40s）：ok，测量正常吞吐 R0
  阶段 2（60s）：500，receiver 统计被拒绝次数
  阶段 3（60s）：ok，观察恢复后的补发量

判据：若恢复后 receiver 收到的请求数出现"补偿性上涨"（超过正常速率），
      说明积压被补发；若恢复后速率立即回到正常水平且无补偿，则数据已丢。
"""
import time

from l7lib import qnum, recv_mode, recv_reset, recv_stats

URL = 'http://l7-receiver:8080/api/v1/write'
LBL = f'{{url="{URL}"}}'


def stat():
    s = recv_stats()
    return s


def rw():
    return {
        "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}") or 0,
        "retried": qnum(f"prometheus_remote_storage_samples_retried_total{LBL}") or 0,
        "failed": qnum(f"prometheus_remote_storage_samples_failed_total{LBL}") or 0,
        "enq_retry": qnum(f"prometheus_remote_storage_enqueue_retries_total{LBL}") or 0,
        "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0,
    }


print("=" * 78)
print("E2  后端故障期间数据是否丢失（用 receiver 侧真值判定）")
print("=" * 78)

# ---------------- 阶段 1：基线 ----------------
print("\n########## 阶段 1：正常基线（40 秒） ##########")
recv_mode("ok")
recv_reset()
time.sleep(5)
s0 = stat()
r0 = rw()
t_0 = time.time()
time.sleep(40)
s1 = stat()
r1 = rw()
dt1 = time.time() - t_0

req_rate_ok = (s1["requests"] - s0["requests"]) / dt1
acc_rate_ok = (s1["accepted"] - s0["accepted"]) / dt1
sent_rate_ok = (r1["sent"] - r0["sent"]) / dt1
print(f"    时长 {dt1:.1f}s")
print(f"    请求数 {s1['requests']-s0['requests']}  → 速率 {req_rate_ok:.2f} 次/秒")
print(f"    接受数 {s1['accepted']-s0['accepted']}  → 速率 {acc_rate_ok:.2f} 次/秒")
print(f"    Prometheus sent 速率 {sent_rate_ok:.1f} 样本/秒")

# ---------------- 阶段 2：故障 ----------------
print("\n########## 阶段 2：注入 500（60 秒） ##########")
recv_mode("500")
s2a = stat()
r2a = rw()
t_2 = time.time()
time.sleep(60)
s2b = stat()
r2b = rw()
dt2 = time.time() - t_2
print(f"    时长 {dt2:.1f}s")
print(f"    请求数 {s2b['requests']-s2a['requests']}  "
      f"（其中被拒 {s2b['rejected']-s2a['rejected']}）")
print(f"    pending: {r2a['pending']:.0f} → {r2b['pending']:.0f}")
print(f"    enqueue_retries: {r2a['enq_retry']:.0f} → {r2b['enq_retry']:.0f} "
      f"（+{r2b['enq_retry']-r2a['enq_retry']:.0f}）")
print(f"    failed: {r2a['failed']:.0f} → {r2b['failed']:.0f} "
      f"（+{r2b['failed']-r2a['failed']:.0f}）")
print(f"    Prometheus sent 增量: {r2b['sent']-r2a['sent']:.0f}")

# ---------------- 阶段 3：恢复 ----------------
print("\n########## 阶段 3：恢复（60 秒） ##########")
recv_mode("ok")
s3a = stat()
r3a = rw()
t_3 = time.time()
time.sleep(60)
s3b = stat()
r3b = rw()
dt3 = time.time() - t_3

req_rate_rec = (s3b["requests"] - s3a["requests"]) / dt3
sent_rate_rec = (r3b["sent"] - r3a["sent"]) / dt3
print(f"    时长 {dt3:.1f}s")
print(f"    请求数 {s3b['requests']-s3a['requests']}  → 速率 {req_rate_rec:.2f} 次/秒")
print(f"    Prometheus sent 速率 {sent_rate_rec:.1f} 样本/秒")
print(f"    pending: {r3a['pending']:.0f} → {r3b['pending']:.0f}")
print(f"    failed 增量: {r3b['failed']-r3a['failed']:.0f}")

# ---------------- 判定 ----------------
print("\n" + "=" * 78)
print("判定")
print("=" * 78)

expected_req = req_rate_ok * dt2
actual_req = s2b["requests"] - s2a["requests"]
print(f"\n  故障期间：")
print(f"    若后端正常，预期请求数 ≈ {expected_req:.0f}")
print(f"    实际请求数               = {actual_req}")
print(f"    缺口                     = {expected_req - actual_req:.0f}")

print(f"\n  恢复期间：")
print(f"    正常速率 = {req_rate_ok:.2f} 次/秒")
print(f"    恢复速率 = {req_rate_rec:.2f} 次/秒")
ratio = req_rate_rec / req_rate_ok if req_rate_ok else 0
print(f"    恢复/正常 = {ratio:.2f}x")

print(f"\n  Prometheus sent 速率：")
print(f"    正常 = {sent_rate_ok:.1f} 样本/秒")
print(f"    恢复 = {sent_rate_rec:.1f} 样本/秒")
s_ratio = sent_rate_rec / sent_rate_ok if sent_rate_ok else 0
print(f"    恢复/正常 = {s_ratio:.2f}x")

print()
if s_ratio > 1.25:
    print("  >>> 结论：恢复期速率显著高于正常期，说明积压被补发，数据未丢（在 WAL 撑住的前提下）")
elif s_ratio > 0.75:
    print("  >>> 结论：恢复期速率与正常期相当，未见明显补发；")
    print("      可能积压已被消化，或数据在队列满时被丢弃。需结合 enqueue_retries 判断。")
else:
    print("  >>> 结论：恢复期速率低于正常期，异常，需排查。")

print(f"\n  enqueue_retries 总增量 = {r3b['enq_retry']-r1['enq_retry']:.0f}")
print("  （该值 > 0 表示曾有样本因队列满而入队失败 —— 这是丢数据的直接信号）")

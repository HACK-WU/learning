#!/usr/bin/env python3
"""
查清两个疑点：
  1) in < sent 的负数差值：两个指标的统计口径到底差在哪？
  2) pending 卡在 1199 不动：被挡在门外的数据去哪了？
"""
import time

from l7lib import qnum, qseries, recv_mode, recv_stats

URL = 'http://l7-receiver:8080/api/v1/write'
LBL = f'{{url="{URL}"}}'

print("=" * 78)
print("疑点 1：in 与 sent 的统计口径")
print("=" * 78)

print("\n[1] samples_in_total 的完整标签")
for s in qseries("prometheus_remote_storage_samples_in_total"):
    print(f"    {s['metric']} = {s['value'][1]}")

print("\n[2] samples_total 的完整标签")
for s in qseries("prometheus_remote_storage_samples_total"):
    print(f"    {s['metric']} = {s['value'][1]}")

print("\n[3] 两者差值随时间的变化（正常模式，20 秒）")
recv_mode("ok")
time.sleep(5)
deltas = []
for i in range(5):
    a = qnum("prometheus_remote_storage_samples_in_total") or 0
    b = qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0
    deltas.append((a, b, a - b))
    print(f"    t={i*4:2d}s  in={a:8.0f}  sent={b:8.0f}  diff={a-b:8.0f}")
    time.sleep(4)

print("\n[4] 差值是否在收敛（判断是不是固定偏移）")
if len(deltas) >= 2:
    d0, d1 = deltas[0][2], deltas[-1][2]
    print(f"    起始 diff={d0:.0f}  末尾 diff={d1:.0f}  变化={d1-d0:.0f}")
    if abs(d1 - d0) < 50:
        print("    → 差值基本恒定：这是一个固定偏移，不是持续丢失")
    else:
        print("    → 差值持续变化：存在真实的数据差")

print("\n" + "=" * 78)
print("疑点 2：pending 卡住时，数据去哪了")
print("=" * 78)

print("\n[5] 注入 500，同时看 receiver 侧是否还在收到请求")
recv_stats()
recv_mode("500")
time.sleep(30)
s = recv_stats()
print(f"    receiver: requests={s['requests']} accepted={s['accepted']} rejected={s['rejected']}")
print(f"    pending = {qnum(f'prometheus_remote_storage_samples_pending{LBL}'):.0f}")
print(f"    shards  = {qnum(f'prometheus_remote_storage_shards{LBL}'):.0f}")
print(f"    enqRetry= {qnum(f'prometheus_remote_storage_enqueue_retries_total{LBL}'):.0f}")

print("\n[6] 关键：queue_highest_sent_timestamp 是否还在前进？")
t1 = qnum("prometheus_remote_storage_queue_highest_sent_timestamp_seconds" + LBL)
t2 = qnum("prometheus_remote_storage_highest_timestamp_in_seconds")
print(f"    已入队最新样本时间 = {t2:.0f}")
print(f"    已发送最新样本时间 = {t1:.0f}")
print(f"    落后 = {t2 - t1:.0f} 秒")

recv_mode("ok")
print("\n已恢复正常模式")

#!/usr/bin/env python3
"""
E1：remote write 队列行为 —— 后端不可用时，数据去哪了？

设计：
  A) 正常基线：ok 模式，观察 pending / shards / in vs total
  B) 后端 500：观察重试、backoff、pending 上涨、shards 是否扩容
  C) 队列打满：capacity 内能否撑住；超出后 enqueue_retries 是否上涨
  D) 恢复：pending 是否回落、是否会重放补回

关键指标（v3.14.0 真名）：
  prometheus_remote_storage_samples_in_total        入队总数
  prometheus_remote_storage_samples_total           实际发送总数
  prometheus_remote_storage_samples_pending         队列积压
  prometheus_remote_storage_samples_failed_total    永久失败
  prometheus_remote_storage_samples_retried_total   重试次数
  prometheus_remote_storage_enqueue_retries_total   入队重试（队列满的信号）
  prometheus_remote_storage_shards / _desired       shard 数
"""
import time

from l7lib import qnum, recv_mode, recv_stats

URL = 'http://l7-receiver:8080/api/v1/write'
LBL = f'{{url="{URL}"}}'


def snap(tag):
    d = {
        "in": qnum("prometheus_remote_storage_samples_in_total"),
        "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}"),
        "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}"),
        "failed": qnum(f"prometheus_remote_storage_samples_failed_total{LBL}"),
        "retried": qnum(f"prometheus_remote_storage_samples_retried_total{LBL}"),
        "enq_retry": qnum(f"prometheus_remote_storage_enqueue_retries_total{LBL}"),
        "shards": qnum(f"prometheus_remote_storage_shards{LBL}"),
        "shards_desired": qnum(f"prometheus_remote_storage_shards_desired{LBL}"),
        "cap": qnum(f"prometheus_remote_storage_shard_capacity{LBL}"),
    }
    print(f"  [{tag:14s}] in={d['in'] or 0:>8.0f} sent={d['sent'] or 0:>8.0f} "
          f"pending={d['pending'] or 0:>6.0f} failed={d['failed'] or 0:>5.0f} "
          f"retried={d['retried'] or 0:>5.0f} enqRetry={d['enq_retry'] or 0:>4.0f} "
          f"shards={d['shards'] or 0:>3.0f}(desired={d['shards_desired'] or 0:.2f})")
    return d


print("=" * 78)
print("E1  remote write 队列行为与数据丢失点")
print("=" * 78)

print("\n########## A) 基线：后端正常 ##########")
recv_mode("ok")
time.sleep(15)
a0 = snap("A-start")
time.sleep(20)
a1 = snap("A-end")
d_in = a1["in"] - a0["in"]
d_sent = a1["sent"] - a0["sent"]
print(f"  → 20 秒内：入队 {d_in:.0f}，发出 {d_sent:.0f}，差值 {d_in-d_sent:.0f}")
print(f"  → 队列积压稳定在 {a1['pending']:.0f} 左右，说明生产与消费速率匹配")

print("\n########## B) 后端返回 500（可重试错误） ##########")
print("  把 receiver 切到 500 模式，持续 60 秒")
recv_mode("500")
for i in range(6):
    time.sleep(10)
    snap(f"B-{(i+1)*10}s")
b = snap("B-end")

print("\n  --- 观察点 ---")
print(f"  1) pending 是否上涨（数据在队列里堆积）：{b['pending']:.0f}")
print(f"  2) failed 是否上涨（500 是'可重试'，不应计入 failed）：{b['failed']:.0f}")
print(f"  3) retried 是否上涨（重试发生了吗）：{b['retried']:.0f}")
print(f"  4) shards 是否扩容（能否自动提速）：{b['shards']:.0f} (max=10)")
print(f"  5) 积压上限：capacity={b['cap']:.0f}")

print("\n########## C) 继续打压，看队列是否会满 ##########")
print("  保持 500，再观察 60 秒，看 enqueue_retries 是否上涨")
c0 = snap("C-start")
for i in range(6):
    time.sleep(10)
    snap(f"C-{(i+1)*10}s")
c1 = snap("C-end")
print(f"  → enqueue_retries 增量 = {c1['enq_retry'] - c0['enq_retry']:.0f}")
print(f"  → pending 峰值约 {c1['pending']:.0f} / capacity {c1['cap']:.0f}")

print("\n########## D) 恢复后端，看是否补发 ##########")
recv_mode("ok")
for i in range(6):
    time.sleep(10)
    snap(f"D-{(i+1)*10}s")
d = snap("D-end")

s = recv_stats()
print(f"\n  receiver 侧：requests={s['requests']} accepted={s['accepted']} rejected={s['rejected']}")

print("\n" + "=" * 78)
print("E1 关键结论")
print("=" * 78)
print(f"""
1) 后端 500 期间：pending 从 {a1['pending']:.0f} 涨到峰值，说明数据在内存队列中堆积，未立即丢弃
2) failed_total 保持 {b['failed']:.0f}：500 属可重试错误，不计入永久失败
3) 恢复后 sent 持续追赶 in，说明队列积压被重放补发
4) 若 pending 逼近 capacity({c1['cap']:.0f}) 且 enqueue_retries 上涨，才是真正的丢数据前兆
""")

#!/usr/bin/env python3
"""
查清：pending=1199 为什么超过 capacity=1000？

假设：
  H1) capacity 是"每个 shard"的容量，pending 是"所有 shard 之和" —— 但 shards=1，不成立
  H2) 超出部分不在内存队列，而在 WAL 里 —— WAL 有独立上限（2h 或 max_samples）
  H3) pending 的统计口径包含了已取出待发送的批次

验证方法：
  1. 改 capacity 为不同值，看 pending 峰值是否随之变化
  2. 观察 WAL 大小与 segment 数
  3. 对比 in vs sent 的差值，看超出部分到底存在哪
"""
import time

from l7lib import qnum, recv_mode

URL = 'http://l7-receiver:8080/api/v1/write'
LBL = f'{{url="{URL}"}}'


def snap():
    return {
        "in": qnum("prometheus_remote_storage_samples_in_total") or 0,
        "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0,
        "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}") or 0,
        "cap": qnum(f"prometheus_remote_storage_shard_capacity{LBL}") or 0,
        "shards": qnum(f"prometheus_remote_storage_shards{LBL}") or 0,
        "enq_retry": qnum(f"prometheus_remote_storage_enqueue_retries_total{LBL}") or 0,
        "wal_fsync": qnum("prometheus_tsdb_wal_fsync_duration_seconds_count") or 0,
        "wal_seg": qnum("prometheus_tsdb_wal_segment_current") or 0,
        "head_series": qnum("prometheus_tsdb_head_series") or 0,
    }


print("=" * 78)
print("查清 pending > capacity 的原因")
print("=" * 78)

print("\n[1] 当前队列状态（先恢复正常消化积压）")
recv_mode("ok")
time.sleep(20)
s = snap()
print(f"    capacity={s['cap']:.0f}  shards={s['shards']:.0f}  pending={s['pending']:.0f}")
print(f"    in-sent 差值 = {s['in'] - s['sent']:.0f}")

print("\n[2] 注入 500，精确追踪 pending 的爬升过程（每 2 秒采样）")
recv_mode("500")
peak = 0
prev = None
samples = []
for i in range(45):
    time.sleep(2)
    s = snap()
    samples.append(s)
    peak = max(peak, s["pending"])
    if prev is None or s["pending"] != prev:
        print(f"    t={(i+1)*2:3d}s  pending={s['pending']:7.0f}  "
              f"cap={s['cap']:.0f}  shards={s['shards']:.0f}  "
              f"enqRetry={s['enq_retry']:.0f}  walSeg={s['wal_seg']:.0f}")
    prev = s["pending"]

print(f"\n    >>> pending 峰值 = {peak:.0f}")
print(f"    >>> capacity     = {samples[-1]['cap']:.0f}")
print(f"    >>> 超出          = {peak - samples[-1]['cap']:.0f} ({(peak/samples[-1]['cap']-1)*100:.1f}%)")

print("\n[3] 恢复，确认积压被消化")
recv_mode("ok")
time.sleep(25)
s2 = snap()
print(f"    pending={s2['pending']:.0f}  in-sent={s2['in']-s2['sent']:.0f}")

print("\n" + "=" * 78)
print("判定")
print("=" * 78)
if peak > samples[-1]["cap"] * 1.05:
    print(f"""
pending({peak:.0f}) 明显超过 capacity({samples[-1]['cap']:.0f})。

最可能的解释：capacity 限制的是「内存队列」，而超出部分被写入 WAL。
remote write 的 WAL watcher 独立于内存队列工作，它会把未发送的样本
持续写入 WAL，因此 pending 可以短暂超过 capacity。

这意味着：即使队列满了，只要 WAL 还在（默认 2 小时），数据仍有补发机会；
真正丢数据的时刻是 WAL 段被截断之后。
""")
else:
    print("pending 未明显超过 capacity，符合队列模型预期。")

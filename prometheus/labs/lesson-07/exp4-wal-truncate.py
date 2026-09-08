#!/usr/bin/env python3
"""
E4（验证性）：WAL 截断是否依赖"数据已送达后端"

WAL 截断的前提：这些样本已经被 remote write 成功发送。
因此：
  - 后端正常 → 发送成功 → WAL 被截断（段数回落、truncations_total 上涨）
  - 后端故障 → 发送停滞 → WAL 不被截断（段持续累积）

这是"WAL 是 remote write 的兜底，而非独立存储"的直接证据。
"""
import time

from l7lib import qnum, recv_mode

URL = 'http://l7-receiver:8080/api/v1/write'
LBL = f'{{url="{URL}"}}'


def wal():
    return {
        "trunc": qnum("prometheus_tsdb_wal_truncations_total") or 0,
        "seg": qnum("prometheus_tsdb_wal_segment_current") or 0,
        "size": qnum("prometheus_tsdb_wal_storage_size_bytes") or 0,
        "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0,
        "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}") or 0,
    }


print("=" * 78)
print("E4  WAL 截断与 remote write 发送确认的依赖关系")
print("=" * 78)

print("\n########## A) 后端正常：WAL 应该被截断 ##########")
recv_mode("ok")
time.sleep(10)
a0 = wal()
print(f"    起点: truncations={a0['trunc']:.0f} seg={a0['seg']:.0f} "
      f"size={a0['size']/1024:.0f}KB sent={a0['sent']:.0f}")
time.sleep(60)
a1 = wal()
print(f"    60s后: truncations={a1['trunc']:.0f} seg={a1['seg']:.0f} "
      f"size={a1['size']/1024:.0f}KB sent={a1['sent']:.0f}")
print(f"    → 截断次数增量 = {a1['trunc']-a0['trunc']:.0f}")
print(f"    → sent 增量    = {a1['sent']-a0['sent']:.0f}")

print("\n########## B) 后端 500：WAL 应该停止截断 ##########")
recv_mode("500")
time.sleep(10)
b0 = wal()
print(f"    起点: truncations={b0['trunc']:.0f} seg={b0['seg']:.0f} "
      f"size={b0['size']/1024:.0f}KB pending={b0['pending']:.0f}")
time.sleep(60)
b1 = wal()
print(f"    60s后: truncations={b1['trunc']:.0f} seg={b1['seg']:.0f} "
      f"size={b1['size']/1024:.0f}KB pending={b1['pending']:.0f}")
print(f"    → 截断次数增量 = {b1['trunc']-b0['trunc']:.0f}")
print(f"    → WAL 大小增量 = {(b1['size']-b0['size'])/1024:.0f}KB")

print("\n########## C) 恢复后：WAL 应重新开始截断 ##########")
recv_mode("ok")
time.sleep(10)
c0 = wal()
time.sleep(60)
c1 = wal()
print(f"    起点: truncations={c0['trunc']:.0f} seg={c0['seg']:.0f} size={c0['size']/1024:.0f}KB")
print(f"    60s后: truncations={c1['trunc']:.0f} seg={c1['seg']:.0f} size={c1['size']/1024:.0f}KB")
print(f"    → 截断次数增量 = {c1['trunc']-c0['trunc']:.0f}")

print("\n" + "=" * 78)
print("判定")
print("=" * 78)
trunc_ok = a1["trunc"] - a0["trunc"]
trunc_fail = b1["trunc"] - b0["trunc"]
trunc_rec = c1["trunc"] - c0["trunc"]
print(f"\n  后端正常时截断增量 = {trunc_ok:.0f}")
print(f"  后端故障时截断增量 = {trunc_fail:.0f}")
print(f"  恢复之后截断增量   = {trunc_rec:.0f}")
print()
if trunc_ok > 0 and trunc_fail == 0:
    print("  >>> 证实：WAL 截断依赖 remote write 的发送确认。")
    print("      后端故障时 WAL 停止截断（数据在 WAL 中被保留等待重发），")
    print("      这正是 remote write 不丢数据的关键机制。")
else:
    print("  >>> 未观察到预期模式，需结合实际数值解读：")
    print(f"      正常={trunc_ok:.0f} 故障={trunc_fail:.0f} 恢复={trunc_rec:.0f}")

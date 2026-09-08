#!/usr/bin/env python3
"""
E5：remote read 的查询路径与代价

核心问题：remote read 能不能查到本地没有的数据？代价多大？

实验设计（关键：制造"本地没有、远端有"的不对称）：
  l7-prom-rr：本地保留 15 分钟 + remote write 到 VM（远端全量）
  l7-prom-ro：本地保留 15 分钟，仅 remote read，自己不写远端

  两者查同一段"很久以前"的数据 —— 本地早已过期，只能靠 remote read

对照维度：
  A) 本地范围查询（数据在内存/head 里）      —— 基准
  B) 超出本地保留的范围查询（走 remote read） —— 对照
  C) read_recent=false vs true 的差异
  D) 远端查询的样本放大：read-sample-limit 边界
"""
import time

from l7lib import VM, qcount, qnum, qpoints, query, timing

RR = "http://localhost:19102"    # 有 remote_write + remote_read
RO = "http://localhost:19103"    # 只有 remote_read
PROM = "http://localhost:19100"  # 原实例（无 remote read）

print("=" * 78)
print("E5  remote read 查询路径与代价")
print("=" * 78)

now = time.time()

print("\n[1] 三方数据存量对比")
print(f"    {'查询目标':24s} {'l7_card_balance 序列数':>24s}")
for name, host in (("l7-prom(本地+receiver)", PROM),
                   ("l7-prom-rr(本地+VM读写)", RR),
                   ("l7-prom-ro(仅remote read)", RO),
                   ("VictoriaMetrics(远端)", VM)):
    c = qcount("l7_card_balance", host=host)
    print(f"    {name:24s} {c:>24d}")

print("\n[2] 关键对照：查本地已过期、只有远端有的历史数据")
print("    策略：查 3 小时前的数据（本地 retention=15m，必然已过期）")

old_end = now - 3 * 3600
old_start = old_end - 300   # 5 分钟窗口
print(f"    时间窗: {time.strftime('%H:%M:%S', time.localtime(old_start))} "
      f"~ {time.strftime('%H:%M:%S', time.localtime(old_end))}")

for name, host in (("l7-prom-rr(有remote read)", RR),
                   ("l7-prom-ro(仅remote read)", RO),
                   ("l7-prom(无remote read)", PROM)):
    pts, ser = qpoints("l7_card_balance", old_start, old_end, 60, host=host)
    print(f"    {name:26s} 序列={ser:>5d} 点数={pts:>7d}")

print("\n[3] 近期数据（本地有，不走远端）")
recent_start = now - 300
for name, host in (("l7-prom-rr", RR), ("l7-prom-ro", RO), ("l7-prom", PROM)):
    pts, ser = qpoints("l7_card_balance", recent_start, now, 60, host=host)
    print(f"    {name:26s} 序列={ser:>5d} 点数={pts:>7d}")

print("\n[4] 性能对照：同一查询，本地 vs 远端")
q_local = "l7_card_balance"
t_rr = timing(lambda: qcount(q_local, host=RR), n=5)
t_ro = timing(lambda: qcount(q_local, host=RO), n=5)
t_prom = timing(lambda: qcount(q_local, host=PROM), n=5)
print(f"    {'目标':14s} {'中位耗时':>12s} {'最小':>10s} {'最大':>10s}")
for name, t in (("l7-prom-rr", t_rr), ("l7-prom-ro", t_ro), ("l7-prom", t_prom)):
    print(f"    {name:14s} {t['med']:>10.1f}ms {t['min']:>8.1f}ms {t['max']:>8.1f}ms")

print("\n[5] 远端查询的代价：范围越大越贵吗？")
print(f"    {'时间跨度':>10s} {'l7-prom-rr 点数':>18s} {'l7-prom-ro 点数':>18s}")
for span_min in (5, 30, 120, 360):
    s = now - span_min * 60
    pts_rr, _ = qpoints("l7_card_balance", s, now, 60, host=RR)
    pts_ro, _ = qpoints("l7_card_balance", s, now, 60, host=RO)
    print(f"    {span_min:>8d}分 {pts_rr:>18d} {pts_ro:>18d}")

print("\n[6] remote read 的并发与限流参数（本机实测 flag 默认值）")
for m in ("prometheus_remote_read_handler_queries",):
    v = qnum(m, host=RR)
    print(f"    {m} = {v}")

print("\n" + "=" * 78)
print("E5 小结")
print("=" * 78)
print("""
观察要点：
1) l7-prom-ro 本地无数据却能查到 —— 证明 remote read 确实补齐了查询能力
2) 对比 ro 与 rr 在"本地缺失区间"的点数，可判断 remote read 是否真的被调用
3) 耗时对照反映 remote read 的序列化 + 网络开销
""")

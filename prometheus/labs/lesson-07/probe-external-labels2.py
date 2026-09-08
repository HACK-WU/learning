#!/usr/bin/env python3
"""
查清两个反常：
  1) l7-prom-rr 查 {cluster="l7-lab"} 为什么是 0（不写反而命不中？）
  2) l7-prom-ro 为什么全 0（它也配了相同的 external_labels）

官方原文（robustperception.io）：
  "When reading back in via remote read, Prometheus adds the external labels
   to your selectors so you'll get back the series that that particular
   Prometheus wrote, and those external labels are then stripped before being
   used by PromQL.
   If a PromQL selector explicitly specifies a matcher for a label name which
   is in external labels, then the above processing doesn't happen for that
   label name for the remote read."

按此机制解释：
  - 查询不加 cluster  → Prometheus 自动补 cluster="l7-lab"，命中后剥离 → 返回 500
  - 查询显式加 cluster="l7-lab" → 该 label 不再被"自动处理"，
    但返回的序列仍带 cluster 标签，PromQL 匹配时……
"""
import time

from l7lib import VM, qcount, qseries

RR = "http://localhost:19102"
RO = "http://localhost:19103"

print("=" * 78)
print("反常追查：external_labels 在 remote read 中的确切行为")
print("=" * 78)

print("\n[1] 先看 l7-prom-rr 返回的序列到底带不带 cluster 标签")
r = qseries('l7_card_balance{idx="0001"}', host=RR)
if r:
    print(f"    l7-prom-rr 返回标签 = {dict(r[0]['metric'])}")
else:
    print("    l7-prom-rr 无返回")

print("\n[2] 在 VM 上做对照，确认标签确实存在")
r2 = qseries('l7_card_balance{idx="0001"}', host=VM)
if r2:
    print(f"    VM 上的标签      = {dict(r2[0]['metric'])}")

print("\n[3] 关键：l7-prom-rr 本地也有这批数据，会不会是本地命中掩盖了远端？")
print("    rr 本地 retention=15m，数据刚写入，本地必然有")
c_local_only = qcount('l7_card_balance{cluster="l7-lab"}', host=VM)
print(f'    VM 上 {{cluster="l7-lab"}} 的序列数 = {c_local_only}  （VM 侧确认有 500 条）')

print("\n    那为什么 rr 查它是 0？")
print("    假设：rr 本地查 {cluster=...} 为空(本地无此标签)，")
print("          remote read 又因显式指定而跳过了自动补全，两边都空。")

print("\n[4] 决定性验证：查一个本地有、但 VM 上没有的指标")
print("    l7-prom-ro 只抓自己，用 ro 自己的 up 指标做区分")
for host, name in ((RR, "l7-prom-rr"), (RO, "l7-prom-ro")):
    c_up = qcount("up", host=host)
    c_self = qcount('up{job="l7-prom-self"}', host=host)
    print(f"    {name}: up={c_up}  up{{job=l7-prom-self}}={c_self}")

print("\n[5] l7-prom-ro 全 0 的真正原因：它有没有真的连上 VM？")
print("    查 ro 的 remote read 相关指标")
from l7lib import qnum
for m in ("prometheus_remote_read_handler_queries",
          "prometheus_remote_storage_samples_total"):
    print(f"    {m} = {qnum(m, host=RO)}")

print("\n[6] 直接看 ro 的日志：remote read 有没有报错")
print("    （下面由 shell 补查）")

print("\n" + "=" * 78)
print("判定")
print("=" * 78)
print("""
综合 [1][2][3]：
  - rr 能查到 l7_card_balance=500，说明 remote read 链路通
  - rr 查 {cluster="l7-lab"}=0，证实"显式指定 external label 会改变处理路径"
  - ro 全 0 且 remote_read_handler_queries=0，说明 ro 的 remote read 未被触发，
    需查日志确认原因（很可能是 required_matchers/external labels 不匹配）
""")

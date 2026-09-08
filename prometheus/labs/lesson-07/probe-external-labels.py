#!/usr/bin/env python3
"""
验证假设：remote read 查不到数据，是因为 external_labels 被自动附加到选择器上。

官方机制（robustperception.io / Prometheus 文档）：
  remote read 时，Prometheus 会把 external_labels 加到查询选择器中，
  以便只取回"这个 Prometheus 自己写进去的"数据。

验证方法：
  1) 查 VM 里数据的真实标签（是否带 cluster/replica）
  2) 对比 filter_external_labels: true / false 两种配置下的查询结果
  3) 用显式写出 external label 的查询，看能否命中
"""
import time

from l7lib import VM, qcount, qseries

print("=" * 78)
print("验证：external_labels 如何影响 remote read")
print("=" * 78)

print("\n[1] VM 里 l7_card_balance 的真实标签是什么？")
r = qseries('l7_card_balance{idx="0001"}', host=VM)
if r:
    m = dict(r[0]["metric"])
    print(f"    完整标签 = {m}")
    has_cluster = "cluster" in m
    has_replica = "replica" in m
    print(f"    带 cluster 标签？ {has_cluster}")
    print(f"    带 replica 标签？ {has_replica}")
else:
    print("    未查到，改用 count 探针")
    print(f"    count = {qcount('l7_card_balance', host=VM)}")
    r2 = qseries("l7_card_balance", host=VM)
    if r2:
        print(f"    样例标签 = {dict(r2[0]['metric'])}")

print("\n[2] 统计 VM 里带/不带 cluster 标签的序列数")
c_all = qcount("l7_card_balance", host=VM)
c_with = qcount('l7_card_balance{cluster="l7-lab"}', host=VM)
c_without = qcount('l7_card_balance{cluster=""}', host=VM)
print(f"    l7_card_balance                    = {c_all}")
print(f'    l7_card_balance{{cluster="l7-lab"}}  = {c_with}')
print(f'    l7_card_balance{{cluster=""}}        = {c_without}')

print("\n[3] 关键对照：l7-prom-ro（仅 remote read）查带 external label 的查询")
for q in ("l7_card_balance",
          'l7_card_balance{cluster="l7-lab"}',
          'l7_card_balance{cluster="l7-lab",replica="0"}'):
    c = qcount(q, host="http://localhost:19103")
    print(f"    {q:52s} = {c}")

print("\n[4] 对照：l7-prom-rr（自己也写 VM）查同样的查询")
for q in ("l7_card_balance",
          'l7_card_balance{cluster="l7-lab"}'):
    c = qcount(q, host="http://localhost:19102")
    print(f"    {q:52s} = {c}")

print("\n" + "=" * 78)
print("结论")
print("=" * 78)
print("""
如果 [3] 中带 cluster="l7-lab" 的查询能命中而不带的不行，
则证实：remote read 会把 external_labels 附加到选择器上。
l7-prom-ro 从不写远端，因此其 external_labels 组合在 VM 中不存在，
导致所有查询都返回空 —— 这正是"remote read 配了却查不到"的经典原因。
""")

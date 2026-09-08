"""诊断：正则匹配器的真实成本模型 —— 为什么无界正则有时反而更快？

假设（必须验证，不能凭常识下结论）：
  A. 上一轮的"反直觉"是噪声 —— 中位差 36ms，而 min~max 区间重叠严重
     （等值 110.6~179.9，无界正则 108.1~125.8）。需要大样本。
  B. 成本由「候选集扫描量」决定，不是「正则是否无界」。
     命中 1 条时，无论怎么写都要扫一遍候选集，开销相近。

验证方法：
  1. 大样本（n=50）比较，看差异是否稳定超过噪声带。
  2. 改变**候选集大小**（20000 vs 100），看成本是否随之变化。
     若成本随候选集增大而增大 → 说明是"扫描候选集"主导，支持 B。
"""
import statistics
import time

from l6lib import app_get, query, now


def bench_n(expr, n=50):
    els = []
    for _ in range(n):
        t0 = time.perf_counter()
        query(expr)
        els.append((time.perf_counter() - t0) * 1000)
    return statistics.median(els), min(els), max(els), statistics.stdev(els)


print("== 1. 大样本重测（n=50）：差异是否稳定？ ==")
cases = [
    ('l6_card_metric{idx="000123"}', "等值"),
    ('l6_card_metric{idx=~"000123"}', "正则无元字符"),
    ('l6_card_metric{idx=~".*000123"}', "无界正则 .* 前缀"),
    ('l6_card_metric{idx=~".+"}', "全匹配 .+"),
]
for expr, label in cases:
    m, lo, hi, sd = bench_n(expr, 50)
    nhit = len(query(expr) or [])
    print(f"   {label:<18} 命中={nhit:<6} 中位={m:>7.1f}ms "
          f"min~max={lo:.1f}~{hi:.1f}  stdev={sd:>5.1f}")

print()
print("== 2. 决定性对照：候选集大小 vs 单次查询成本 ==")
print("   若成本随候选集增大 → 扫描候选集是主因（支持假设 B）")
for n in [100, 2000, 20000]:
    print(app_get(f"/cardinality?n={n}"))
    time.sleep(8)
    for expr, label in [
        ('l6_card_metric{idx="000123"}', "等值"),
        ('l6_card_metric{idx=~".*000123"}', "无界正则"),
    ]:
        m, lo, hi, sd = bench_n(expr, 40)
        nhit = len(query(expr) or [])
        print(f"   候选集={n:<6} {label:<10} 命中={nhit:<4} 中位={m:>7.1f}ms "
              f"({lo:.1f}~{hi:.1f})")

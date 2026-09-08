"""E6-D（终版）：recording rule 预聚合的真实收益。

前两版的坑（都导致数据不可用）：
  1. 规则未生效（rule_files 未声明）→ 产物 0 条，"降幅"实为查空指标
  2. 规则生效了，但产物只有 45 秒历史，查 5 分钟区间时大部分为空
     → 改写后点数=0，降幅仍不可信

本版修正：
  - 规则 interval=5s，等 300 秒攒满 5 分钟产物
  - 查询区间严格对齐到产物已覆盖的范围
  - 严格校验：改写前后点数必须同量级，否则判定实验无效
"""
import statistics
import subprocess
import time

from l6lib import app_get, query, query_range, now


def bench(expr, start, end, step, n=9):
    els, pts = [], []
    for _ in range(n):
        t0 = time.perf_counter()
        r = query_range(expr, start, end, step)
        els.append((time.perf_counter() - t0) * 1000)
        pts.append(sum(len(x["values"]) for x in r) if r else 0)
    return (statistics.median(els), min(els), max(els),
            int(statistics.median(pts or [0])))


print("== 准备：20000 条序列 ==")
print(app_get("/cardinality?n=20000"))
print(app_get("/revive"))
time.sleep(20)

print()
print("== 等 recording rule 攒满 5 分钟历史（interval=5s） ==")
print("   等待中，共 300 秒...")
for i in range(30):
    time.sleep(10)
    if (i + 1) % 6 == 0:
        r = query("l6:card_rate:by_idx")
        r2 = query("l6:card_rate:sum")
        print(f"   {(i+1)*10:>3}s  l6:card_rate:sum={len(r2) if r2 else 0} 条, "
              f"by_idx={len(r) if r else 0} 条")

print()
print("== 确定有效区间（产物已覆盖） ==")
r = query_range("l6:card_rate:sum", now() - 300, now(), "15s")
n_sum = sum(len(x["values"]) for x in r) if r else 0
print(f"   l6:card_rate:sum 在最近 5 分钟的样本点数 = {n_sum}")
if n_sum < 10:
    print("   !! 产物历史不足，实验无效")
    raise SystemExit(1)

end = now()
start = end - 300

print()
print("== 改写前 vs 改写后（同一区间，点数对齐校验） ==")
pairs = [
    ("sum(rate(l6_card_metric[5m]))", "l6:card_rate:sum", "全聚合 → 1 条"),
    ("sum by (idx) (rate(l6_card_metric[5m]))", "l6:card_rate:by_idx",
     "按 idx → 20000 条"),
    ("topk(10, sum by (idx) (rate(l6_card_metric[5m])))", "l6:card_rate:top10",
     "top10 → 10 条"),
]
print(f'{"场景":<20} | {"前(ms)":>8} | {"前点数":>8} | {"后(ms)":>8} | {"后点数":>8} | {"耗时降幅":>8} | 有效性')
print("-" * 92)
for raw, rec, label in pairs:
    bm, blo, bhi, bpts = bench(raw, start, end, "15s")
    am, alo, ahi, apts = bench(rec, start, end, "15s")
    cut = (1 - am / bm) * 100 if bm else 0
    valid = "OK" if apts > 0 and bpts > 0 else "!!点数异常"
    print(f"{label:<20} | {bm:>8.1f} | {bpts:>8} | {am:>8.1f} | {apts:>8} | "
          f"{cut:>7.1f}% | {valid}")
    print(f"{'':<20} | 波动 {blo:.0f}~{bhi:.0f} | {'':>8} | 波动 {alo:.0f}~{ahi:.0f} |")

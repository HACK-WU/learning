"""E6：rate() 的成本 + recording rule 改写 —— 回答课4/课5 的伏笔。

课4 伏笔：「慢组是快组 5~7 倍耗时，为什么贵、怎么量化、怎么写才便宜」
课5 伏笔：「规则里用了 rate(...)[10s]，它为什么贵」

三组对照：
  A. rate 的 range 长度对成本的影响：[1m] vs [5m] vs [1h]
  B. 子查询 rate(...[5m])[10s:10s] 的成本 —— 课5 规则的写法
  C. recording rule 预聚合前后的成本对比
"""
import statistics
import time

from l6lib import app_get, query, query_range, now


def bench(expr, start, end, step, n=7):
    els, pts = [], []
    for _ in range(n):
        t0 = time.perf_counter()
        r = query_range(expr, start, end, step)
        els.append((time.perf_counter() - t0) * 1000)
        pts.append(sum(len(x["values"]) for x in r) if r else 0)
    return (statistics.median(els), min(els), max(els),
            int(statistics.median(pts or [0])))


print("== 准备：5000 条序列，攒够数据 ==")
print(app_get("/cardinality?n=5000"))
print(app_get("/revive"))
print(app_get("/unbreak"))
time.sleep(30)      # 攒数据，确保 rate 有足够样本

end = now()

print()
print("== 对照 A：rate 的 range 长度 ==")
print(f'{"表达式":<34} | {"点数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 76)
for rng in ["1m", "5m", "30m", "1h"]:
    expr = f"sum(rate(l6_requests_total[{rng}]))"
    m, lo, hi, pts = bench(expr, end - 300, end, "15s")
    print(f"{expr:<34} | {pts:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

print()
print("== 对照 B：子查询（课5 规则的写法） ==")
print("   课5 用了 rate(...)[10s]，这里对比加子查询与不加的差别")
cases_b = [
    ("sum(rate(l6_requests_total[5m]))", "普通 rate"),
    ("max_over_time(sum(rate(l6_requests_total[5m]))[10s:10s])", "子查询 [10s:10s]"),
    ("max_over_time(sum(rate(l6_requests_total[5m]))[1m:10s])", "子查询 [1m:10s]"),
    ("max_over_time(sum(rate(l6_requests_total[5m]))[10m:10s])", "子查询 [10m:10s]"),
]
print(f'{"表达式":<52} | {"点数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 96)
for expr, label in cases_b:
    m, lo, hi, pts = bench(expr, end - 300, end, "15s")
    print(f"{label:<52} | {pts:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

print()
print("== 对照 C：高基数聚合 vs 预聚合 ==")
cases_c = [
    ("sum by (idx) (rate(l6_card_metric[5m]))", "按 idx 聚合（5000 组）"),
    ("sum(rate(l6_card_metric[5m]))", "全聚合成 1 条"),
    ("count(l6_card_metric)", "只数序列数"),
]
print(f'{"表达式":<42} | {"点数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 86)
for expr, label in cases_c:
    m, lo, hi, pts = bench(expr, end - 300, end, "15s")
    print(f"{label:<42} | {pts:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

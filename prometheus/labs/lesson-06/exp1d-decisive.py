"""E1 决定性对照：成本到底跟着什么走？

三组对照，每组都把「点数」与「序列数」解耦：
  A. 序列数固定(20000)，点数变化（改 step）      → 若成本随点数涨，说明点数主导
  B. 点数固定(~20)，序列数变化（1 vs 20000）     → 若成本不动，说明序列数不是主因
  C. 聚合掉基数后 vs 不聚合                      → 验证 topk/sum 的降本效果
"""
import statistics
import time

from l6lib import app_get, query, query_range, now


def bench(expr, start, end, step, n=7):
    els, pts, nser = [], [], []
    for _ in range(n):
        t0 = time.perf_counter()
        r = query_range(expr, start, end, step)
        els.append((time.perf_counter() - t0) * 1000)
        if r:
            pts.append(sum(len(x["values"]) for x in r))
            nser.append(len(r))
    return (statistics.median(els), min(els), max(els),
            int(statistics.median(pts or [0])), int(statistics.median(nser or [0])))


print("== 准备：20000 条序列 ==")
print(app_get("/cardinality?n=20000"))
time.sleep(10)
end = now()

print()
print("== 对照 A：序列数固定 20000，只改 step（点数变化） ==")
print(f'{"step":>6} | {"点数":>7} | {"序列数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 62)
for step in ["1s", "5s", "15s", "60s", "300s"]:
    m, lo, hi, pts, ns = bench("topk(20000, l6_card_metric)", end - 300, end, step)
    print(f"{step:>6} | {pts:>7} | {ns:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

print()
print("== 对照 B：点数固定(~20)，只改序列数 ==")
print(f'{"序列数":>8} | {"点数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 52)
for nsel in [1, 10, 100, 1000, 20000]:
    m, lo, hi, pts, ns = bench(f"topk({nsel}, l6_card_metric)", end - 300, end, "15s")
    print(f"{nsel:>8} | {pts:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

print()
print("== 对照 C：不聚合 vs 聚合掉基数（成本对比） ==")
print(f'{"写法":>28} | {"点数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 72)
cases = [
    ("topk(20000, l6_card_metric)", "原始 20000 条"),
    ("sum(l6_card_metric)", "sum 聚合成 1 条"),
    ("avg(l6_card_metric)", "avg 聚合成 1 条"),
    ("sum by (job) (l6_card_metric)", "sum by(job) 聚合"),
]
for expr, label in cases:
    m, lo, hi, pts, ns = bench(expr, end - 300, end, "15s")
    print(f"{label:>28} | {pts:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

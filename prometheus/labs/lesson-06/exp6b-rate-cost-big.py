"""E6（放大版）：用高基数把 rate 成本放大到远超 ~120ms 固定开销。

上一版失败原因：l6_requests_total 只有 1 条序列，成本淹没在
固定开销（网络+解析，实测 ~120ms，波动 ±30ms）里。

本版：对 20000 条序列做 rate，把成本放大到可观测。
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


print("== 准备：20000 条序列，攒 60 秒数据 ==")
print(app_get("/cardinality?n=20000"))
print(app_get("/revive"))
time.sleep(60)

end = now()

print()
print("== 对照 A：rate 的 range 长度（20000 条序列） ==")
print(f'{"range":>8} | {"点数":>8} | {"中位(ms)":>9} | {"min~max":>16} | {"相对1m":>8}')
print("-" * 62)
base = None
for rng in ["1m", "5m", "15m", "30m", "1h"]:
    expr = f"sum(rate(l6_card_metric[{rng}]))"
    m, lo, hi, pts = bench(expr, end - 300, end, "15s", n=9)
    if base is None:
        base = m
    print(f"{rng:>8} | {pts:>8} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f} | {m/base:>7.2f}x")

print()
print("== 对照 B：子查询的 range 长度（课5 规则写法） ==")
print(f'{"子查询窗口":>12} | {"点数":>8} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 58)
for win in ["10s", "1m", "5m", "30m"]:
    expr = f"max_over_time(sum(rate(l6_card_metric[5m]))[{win}:10s])"
    m, lo, hi, pts = bench(expr, end - 300, end, "15s", n=9)
    print(f"{win:>12} | {pts:>8} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

print()
print("== 对照 C：聚合维度的成本（决定要不要做 recording rule） ==")
cases = [
    ("sum(rate(l6_card_metric[5m]))", "全聚合 → 1 条"),
    ("sum by (idx) (rate(l6_card_metric[5m]))", "按 idx → 20000 条"),
    ("topk(10, sum by (idx) (rate(l6_card_metric[5m])))", "先聚合再 topk10"),
]
print(f'{"写法":<46} | {"点数":>8} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 92)
for expr, label in cases:
    m, lo, hi, pts = bench(expr, end - 300, end, "15s", n=9)
    print(f"{label:<46} | {pts:>8} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

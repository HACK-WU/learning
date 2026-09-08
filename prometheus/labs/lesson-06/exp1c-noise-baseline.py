"""E1（方案三）：先测噪声基线，再确定能放大到显著的最小负载。

前两个方案失败的原因（保留为教学素材）：
- 方案一 prometheus_engine_query_samples_total：自启动累计 counter，
  且按 5s 抓取周期批量更新，无法归因到单次查询。
- 方案二 引擎直方图 inner_eval 差值：同样受 5s 抓取周期限制，
  5 次查询里只有 1 次采到增量（+7 次计数），其余 4 次为 0。

方案三：墙钟耗时 + 重复采样取中位数。前提是先把**负载放大到远超噪声**。
"""
import statistics
import time

from l6lib import app_get, query, query_range, now


def bench(expr, start, end, step, n=5):
    """重复 n 次，返回 (中位数ms, 最小值ms, 最大值ms, 返回点数)。"""
    els, pts = [], []
    for _ in range(n):
        t0 = time.perf_counter()
        r = query_range(expr, start, end, step)
        els.append((time.perf_counter() - t0) * 1000)
        pts.append(sum(len(x["values"]) for x in r) if r else 0)
    return (statistics.median(els), min(els), max(els),
            int(statistics.median(pts)))


print("== 噪声基线：同一查询跑 10 次 ==")
end = now()
els = []
for _ in range(10):
    t0 = time.perf_counter()
    query("l6_requests_total")
    els.append((time.perf_counter() - t0) * 1000)
print(f"   瞬时查询 median={statistics.median(els):.1f}ms "
      f"min={min(els):.1f} max={max(els):.1f} "
      f"波动={max(els)-min(els):.1f}ms")
print("   → 这是网络+解析的固定开销，后续要放大到远超此值")

print()
print("== 放大实验：基数 × 时间窗 交叉，看信号是否浮出噪声 ==")
print(app_get("/cardinality?n=20000"))
time.sleep(10)

print(f'{"序列数":>8} | {"时间窗":>7} | {"step":>5} | {"点数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 72)
end = now()
for nsel in [1, 500, 5000, 20000]:
    for win, step in [(300, "15s"), (3600, "15s")]:
        expr = f"topk({nsel}, l6_card_metric)"
        m, lo, hi, pts = bench(expr, end - win, end, step, n=5)
        print(f"{nsel:>8} | {win:>5}s | {step:>5} | {pts:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

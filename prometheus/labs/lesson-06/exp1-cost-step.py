"""E1（修正版）：查询成本的三维量化。

修正要点：
- 引擎指标 prometheus_engine_query_samples_total 本身按 5s 抓取，
  用瞬时差采样会漏采。改为「查询前后各等一个抓取周期（7s）再取差」。
- 每个配置重复 3 次取中位数，抵消抖动。

三组对照：
  A. step 不同（时间窗固定 5m）
  B. 时间窗不同（step 固定 15s）
  C. 基数不同（时间窗与 step 固定）
"""
import statistics
import time

from l6lib import app_get, query, query_range, now

STAT = "sum(prometheus_engine_query_samples_total)"


def stat_val():
    r = query(STAT)
    return float(r[0]["value"][1]) if r else 0.0


def measure(expr, start, end, step, wait=7.0):
    """测一次：返回 (耗时ms, 返回点数, 处理样本数)。"""
    before = stat_val()
    time.sleep(wait)                       # 让 before 值被抓取落定
    before = stat_val()

    t0 = time.perf_counter()
    r = query_range(expr, start, end, step)
    el = (time.perf_counter() - t0) * 1000

    time.sleep(wait)                       # 等增量被抓取
    after = stat_val()

    npts = sum(len(x["values"]) for x in r) if r else 0
    return el, npts, after - before


def run3(expr, start, end, step):
    """重复 3 次取中位数。"""
    els, pts, smps = [], [], []
    for _ in range(3):
        e, p, s = measure(expr, start, end, step)
        els.append(e)
        pts.append(p)
        smps.append(s)
    return statistics.median(els), int(statistics.median(pts)), statistics.median(smps)


print("== 准备：2000 条高基数序列 ==")
print(app_get("/cardinality?n=2000"))
time.sleep(8)

end = now()
start = end - 300

print()
print("== 对照 A：时间窗固定 5m，step 变化 ==")
print(f'{"step":>6} | {"返回点数":>8} | {"处理样本数":>10} | {"耗时(ms)":>9}')
print("-" * 48)
for step in ["1s", "5s", "15s", "60s"]:
    el, pts, smp = run3("l6_requests_total", start, end, step)
    print(f"{step:>6} | {pts:>8} | {smp:>10.0f} | {el:>9.1f}")

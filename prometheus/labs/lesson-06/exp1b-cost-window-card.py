"""E1 对照 B / C：时间窗 与 基数 对成本的作用。"""
import statistics
import time

from l6lib import app_get, query, query_range, now

STAT = "sum(prometheus_engine_query_samples_total)"


def stat_val():
    r = query(STAT)
    return float(r[0]["value"][1]) if r else 0.0


def measure(expr, start, end, step, wait=7.0):
    stat_val()
    time.sleep(wait)
    before = stat_val()
    t0 = time.perf_counter()
    r = query_range(expr, start, end, step)
    el = (time.perf_counter() - t0) * 1000
    time.sleep(wait)
    after = stat_val()
    npts = sum(len(x["values"]) for x in r) if r else 0
    return el, npts, after - before


def run3(expr, start, end, step):
    els, pts, smps = [], [], []
    for _ in range(3):
        e, p, s = measure(expr, start, end, step)
        els.append(e)
        pts.append(p)
        smps.append(s)
    return statistics.median(els), int(statistics.median(pts)), statistics.median(smps)


print("== 准备 ==")
print(app_get("/cardinality?n=2000"))
time.sleep(8)

end = now()

print()
print("== 对照 B：step 固定 15s，时间窗变化 ==")
print(f'{"时间窗":>8} | {"返回点数":>8} | {"处理样本数":>10} | {"耗时(ms)":>9}')
print("-" * 50)
for win in [300, 900, 1800, 3600]:
    el, pts, smp = run3("l6_requests_total", end - win, end, "15s")
    print(f"{win:>6}s | {pts:>8} | {smp:>10.0f} | {el:>9.1f}")

print()
print("== 对照 C：时间窗 5m / step 15s 固定，基数变化 ==")
print(f'{"基数":>8} | {"命中序列":>8} | {"处理样本数":>10} | {"耗时(ms)":>9}')
print("-" * 50)
for n in [1, 100, 1000, 2000]:
    print(app_get(f"/cardinality?n={n}"))
    time.sleep(8)                       # 等新基数被抓取
    # 用 topk 精确控制命中序列数
    expr = f"topk({n}, l6_card_metric)" if n > 1 else "topk(1, l6_card_metric)"
    el, pts, smp = run3(expr, end - 300, end, "15s")
    nhit = len(query(expr) or [])
    print(f"{n:>8} | {nhit:>8} | {smp:>10.0f} | {el:>9.1f}")

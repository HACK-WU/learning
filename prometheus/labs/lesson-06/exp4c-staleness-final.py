"""E4/E5（终版）：用 1 秒粒度 看清 stale marker 的插入时刻。

关键修正：
1. 采样粒度从 5s 降到 1s，才能看清"下一次抓取"这个瞬间。
2. 用 /cardinality?n=0 清空高基数序列，避免干扰（否则 kill 后
   l6_card_metric 仍在，抓取仍是 200）。
3. 对照 query.lookback-delta：改变它，看边界是否移动。
   —— 这是证明 5m 这个数字真实存在的决定性实验。

理论预期：
  /kill  → 抓取成功、序列消失 → 插入 stale marker → 立刻查不到（~1 个抓取周期）
  /break → 抓取失败           → 不插 stale marker → 数据存活到 lookback delta（5m）
"""
import time

from l6lib import app_get, query, now

EXPR = "l6_concurrency"


def probe_at(t):
    r = query(EXPR, t=t)
    if not r or len(r) == 0:
        return 0, None
    return len(r), float(r[0]["value"][1])


def run(title, action, recover, deltas, gran=1):
    print("=" * 64)
    print(title)
    print("=" * 64)
    app_get("/unbreak")
    app_get("/revive")
    app_get("/cardinality?n=0")
    time.sleep(8)
    n, v = probe_at(now())
    print(f"基线：序列数={n} 值={v}")

    print(f"执行 {action} → {app_get(action)}")
    t0 = now()
    print(f"T0 = {t0:.3f}（抓取间隔 5s）\n")
    print(f'{"Δ(秒)":>7} | {"序列数":>7} | {"值":>8} | 判定')
    print("-" * 48)
    for d in deltas:
        target = t0 + d
        wait = target - now()
        if wait > 0:
            time.sleep(wait)
        n, v = probe_at(target)
        vs = f"{v:.1f}" if v is not None else "-"
        mark = "有数据" if n else "★无数据"
        print(f"{d:>7} | {n:>7} | {vs:>8} | {mark}")
    print(f"\n{recover} → {app_get(recover)}\n")


# 细粒度看 kill：理论上下一次抓取（≤5s）后就该插入 stale marker
run("E4：/kill（抓取成功，序列消失）—— 1 秒粒度看 stale marker 插入",
    "/kill", "/revive", [1, 2, 3, 4, 5, 6, 7, 8, 10, 15], gran=1)

# break：理论上数据应存活到 lookback delta
run("E5：/break（抓取失败 500）—— 数据应存活到 lookback delta",
    "/break", "/unbreak", [1, 5, 10, 30, 60, 120, 240, 290, 310, 330], gran=1)

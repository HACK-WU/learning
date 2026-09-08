"""E4/E5（重设计）：用「指定历史时间点」查询，精确测 staleness 边界。

上一版失败原因：瞬时查询默认用 now()，而 lookback delta 是 5 分钟，
所以 kill 后 5 分钟内查询仍会命中最后一次样本 —— 但它立刻返回空，
说明**另有机制**（stale marker）在起作用。

本版设计：
  kill 之后立刻记下时刻 T0，然后**固定查询 T0+Δ 这个历史时刻**，
  观察 Δ 取多少时查询变空。这才真正测出"数据活到什么时候"。

对照：
  E4 /kill   → 抓取成功(200)，序列消失 → Prometheus 应插入 stale marker
  E5 /break  → 抓取失败(500)          → Prometheus 不插入 stale marker
"""
import time

from l6lib import app_get, query, now

EXPR = "l6_concurrency"


def probe_at(t):
    """查询指定历史时刻 t 的值。"""
    r = query(EXPR, t=t)
    if not r or len(r) == 0:
        return 0, None
    return len(r), float(r[0]["value"][1])


def run_case(title, action, recover, deltas=(1, 10, 30, 60, 120, 240, 300, 330, 400)):
    print("=" * 62)
    print(title)
    print("=" * 62)
    # 先确保健康
    app_get("/unbreak")
    app_get("/revive")
    time.sleep(8)
    n, v = probe_at(now())
    print(f"基线（动作前）：序列数={n} 值={v}")

    # 执行 kill / break，记录时刻
    print(f"执行 {action} → {app_get(action)}")
    t0 = now()
    print(f"动作时刻 T0 = {t0:.3f}\n")

    print(f'{"Δ(秒)":>7} | {"序列数":>7} | {"值":>8} | 判定')
    print("-" * 50)
    for d in deltas:
        # 等到该时刻之后再查
        target = t0 + d
        wait = target - now()
        if wait > 0:
            time.sleep(wait)
        n, v = probe_at(target)
        vs = f"{v:.1f}" if v is not None else "-"
        mark = "有数据" if n else "★无数据（已断）"
        print(f"{d:>7} | {n:>7} | {vs:>8} | {mark}")

    print(f"\n执行 {recover} → {app_get(recover)}")
    time.sleep(8)
    n, v = probe_at(now())
    print(f"恢复后：序列数={n} 值={v}\n")


run_case("E4：目标消失（/kill，抓取仍返回 200，序列不再暴露）",
         "/kill", "/revive")
run_case("E5：抓取失败（/break，/metrics 返回 HTTP 500）",
         "/break", "/unbreak")

"""诊断：E5 为何 Δ=1s 就无数据？—— 检查查询时刻与 lookback 的交互。

疑点：E4 里 probe_at(t0+1) 有数据，E5 里 probe_at(t0+1) 无数据。
两者的差别只有 kill/break。

假设：
  H1. break 后 target 变 down，Prometheus 对 down 的 target 有额外处理
  H2. probe_at 传的历史时刻 t 落在"最后一次样本之后"，而 lookback delta
      只在**没有 stale marker** 时才向后追溯 5 分钟。
      → 若 E5 也插了 stale marker，则立刻失效（与理论矛盾，需查证）
  H3. 我的 app 在 break 时连 l6_up 都不返回，导致**整个 target 的所有序列**
      都被判定消失 —— 这与 kill（部分序列消失）不同

验证：分别查 l6_up 与 l6_concurrency，看 break 时 l6_up 是否还在。
"""
import time

from l6lib import app_get, query, now


def probe(expr, t=None):
    r = query(expr, t=t)
    return (len(r), float(r[0]["value"][1])) if r and len(r) else (0, None)


print("== 准备 ==")
app_get("/unbreak")
app_get("/revive")
app_get("/cardinality?n=0")
time.sleep(8)
for e in ["l6_concurrency", "l6_up"]:
    n, v = probe(e)
    print(f"   基线 {e:<18} 序列数={n} 值={v}")

print()
print("=" * 64)
print("E5 细查：break 之后，l6_up 与 l6_concurrency 各自的命运")
print("=" * 64)
print("break:", app_get("/break"))
t0 = now()
print(f"T0={t0:.3f}")
print()
print(f'{"Δ(秒)":>6} | {"l6_concurrency":>16} | {"l6_up":>12}')
print("-" * 46)
for d in [1, 3, 5, 8, 12, 20, 40, 80, 160, 300, 310]:
    target = t0 + d
    w = target - now()
    if w > 0:
        time.sleep(w)
    n1, v1 = probe("l6_concurrency", target)
    n2, v2 = probe("l6_up", target)
    s1 = f"{v1:.0f}" if v1 is not None else "无"
    s2 = f"{v2:.0f}" if v2 is not None else "无"
    print(f"{d:>6} | {n1:>7} 值={s1:<7} | {n2:>4} 值={s2}")

print()
print("unbreak:", app_get("/unbreak"))
time.sleep(8)
for e in ["l6_concurrency", "l6_up"]:
    n, v = probe(e)
    print(f"   恢复后 {e:<18} 序列数={n} 值={v}")

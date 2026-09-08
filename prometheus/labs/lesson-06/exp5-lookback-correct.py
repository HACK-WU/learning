"""E5（正解）：lookback delta 的正确验证方式。

前几版失败的原因（重要教训）：
  lookback delta 的作用是「查询时刻 t 时，若 t 处无样本，则**向过去**追溯
  最多 5 分钟内的最近样本」。它**不能**让数据在最后样本时刻之后"延伸"到未来。
  前几版一直在查"未来时刻"，所以永远查不到。

正确验证：
  查一个**固定的历史时刻 T**（T 之前有样本），在断点发生后的不同时间查它，
  看数据何时失效。按理论，只要 T 之后 5 分钟内有 stale marker 或新样本，
  查询结果就会变化。

决定性对照：改变 --query.lookback-delta，看边界是否随之移动。
  —— 若 5m 改成 1m 后边界跟着变，就证明了这个参数的真实作用。
"""
import time

from l6lib import app_get, query, now

EXPR = "l6_concurrency"


def probe_at(t):
    r = query(EXPR, t=t)
    return float(r[0]["value"][1]) if r and len(r) else None


print("== 准备 ==")
app_get("/unbreak")
app_get("/revive")
app_get("/cardinality?n=0")
time.sleep(10)

# 选定一个历史时刻 T：此刻有样本
t_now = now()
T = t_now - 2
print(f"固定历史时刻 T = {T:.3f}（此刻有样本）")
print(f"T 处的值 = {probe_at(T)}")

print()
print("=" * 66)
print("E5-A：/kill（抓取成功，序列消失 → 预期插入 stale marker）")
print("=" * 66)
print("kill:", app_get("/kill"))
tk = now()
print(f"kill 时刻 = {tk:.3f}\n")
print(f'{"kill后(秒)":>10} | {"T 处的值":>10} | 判定')
print("-" * 40)
for d in [1, 3, 5, 8, 12, 20]:
    time.sleep(d - (now() - tk))
    v = probe_at(T)
    print(f"{d:>10} | {str(v):>10} | {'有数据' if v is not None else '★已失效'}")

print()
print("revive:", app_get("/revive"))
time.sleep(10)

print()
print("=" * 66)
print("E5-B：/break（抓取失败 500 → 理论不插 stale marker）")
print("=" * 66)
# 重新选一个有样本的时刻
time.sleep(5)
T2 = now() - 2
print(f"固定历史时刻 T2 = {T2:.3f}，值 = {probe_at(T2)}")
print("break:", app_get("/break"))
tb = now()
print(f"break 时刻 = {tb:.3f}\n")
print(f'{"break后(秒)":>11} | {"T2 处的值":>10} | 判定')
print("-" * 42)
for d in [1, 3, 5, 8, 12, 20, 40, 80, 160, 240, 290, 310]:
    w = d - (now() - tb)
    if w > 0:
        time.sleep(w)
    v = probe_at(T2)
    print(f"{d:>11} | {str(v):>10} | {'有数据' if v is not None else '★已失效'}")

print()
print("unbreak:", app_get("/unbreak"))

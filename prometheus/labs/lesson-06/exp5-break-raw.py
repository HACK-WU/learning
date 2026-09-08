"""E5 诊断（用区间查询看原始样本）：break 后到底发生了什么？

区间查询能返回"每个 step 位置上的值"，比瞬时查询信息量大得多。
若 break 后数据仍存活，区间查询应能看到断点前后的样本。
"""
import time

from l6lib import app_get, query_range, now

EXPR = "l6_concurrency"


def show(start, end, step, label):
    r = query_range(EXPR, start, end, step)
    if not r:
        print(f"   {label}: 无结果")
        return
    vals = r[0]["values"]
    print(f"   {label}: {len(vals)} 个样本点")
    for ts, v in vals:
        print(f"      {ts} -> {v}")


print("== 准备 ==")
app_get("/unbreak")
app_get("/revive")
app_get("/cardinality?n=0")
time.sleep(10)

t0 = now()
print(f"T0 = {t0:.3f}")
print()
print("== 1. break 之前：查 T0 前 60 秒 ==")
show(t0 - 60, t0, "5s", "break 前")

print()
print("== 2. 执行 break ==")
print(app_get("/break"))
tb = now()
print(f"break 时刻 = {tb:.3f}")
time.sleep(30)   # 让 30 秒过去，跨越多个抓取周期

print()
print("== 3. break 之后 30 秒：查 tb-60 ~ tb+30 ==")
show(tb - 60, now(), "5s", "break 后（含断点前后）")

print()
print("== 4. 关键：查询 break 之后的时刻，数据还在吗？ ==")
for d in [5, 10, 20, 40]:
    r = query_range(EXPR, tb + d - 2, tb + d + 2, "1s")
    n = sum(len(x["values"]) for x in r) if r else 0
    print(f"   break 后 +{d:>3}s 附近（±2s，step=1s）：{n} 个样本点")

print()
print("== 5. 恢复 ==")
print(app_get("/unbreak"))
time.sleep(10)
show(now() - 30, now(), "5s", "恢复后")

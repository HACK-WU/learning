"""诊断：传 t 参数 与 不传 t 参数，行为是否一致？

疑点：E5 里 Δ=1s 就查不到，而 lookback delta=5m。
关键怀疑：query(expr, t=T) 中的 T 若是"未来时刻"，行为可能不同。

对比四种查询方式：
  1. 不传 t（用服务端 now）
  2. 传 t = 当前真实时刻
  3. 传 t = 最后样本时刻
  4. 区间查询（明确给 start/end）
"""
import time

from l6lib import _wget, app_get, query, query_range, now

EXPR = "l6_concurrency"
q = _wget  # 复用


def raw_get(url):
    import json
    out = _wget(url)
    try:
        d = json.loads(out)
    except Exception:
        return None, out[:200]
    return d, None


print("== 准备：确保有数据 ==")
app_get("/unbreak")
app_get("/revive")
app_get("/cardinality?n=0")
time.sleep(8)

n, v = query(EXPR), None
print("   不传 t：", "有数据" if n else "无数据")

t_now = now()
print()
print("== 对比 1：不传 t ==")
d, err = raw_get(f"/api/v1/query?query={EXPR}")
if d:
    print("   result:", d["data"]["result"])

print()
print("== 对比 2：传 t = 当前时刻 ==")
d, err = raw_get(f"/api/v1/query?query={EXPR}&time={t_now}")
if d:
    print("   result:", d["data"]["result"])

print()
print("== 对比 3：传 t = 10 秒前 ==")
d, err = raw_get(f"/api/v1/query?query={EXPR}&time={t_now - 10}")
if d:
    print("   result:", d["data"]["result"])

print()
print("== 对比 4：区间查询 最近 60 秒 ==")
d, err = raw_get(f"/api/v1/query_range?query={EXPR}&start={t_now-60}&end={t_now}&step=5s")
if d:
    r = d["data"]["result"]
    print("   序列数:", len(r))
    if r:
        print("   样本点:", r[0]["values"][:8])
        print("   样本点总数:", len(r[0]["values"]))

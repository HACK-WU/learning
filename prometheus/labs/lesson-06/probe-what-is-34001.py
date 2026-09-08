"""诊断：34001 是什么？时间窗为何不影响样本数？

假设：prometheus_engine_query_samples_total 统计的是**本次查询从 TSDB
读出的全部样本**（受 query.max-samples 上限保护），而 34001 = 上限 50000000
显然不是。需要查证它到底度量什么。
"""
import time

from l6lib import query, query_range, now

print("== 1. 该指标的原始形态（不加 sum） ==")
r = query("prometheus_engine_query_samples_total")
for s in r or []:
    print("   ", s["metric"], "=", s["value"][1])

print()
print("== 2. 查 query.max-samples 上限 ==")
r = query("prometheus_engine_query_samples_total")
# 直接看 flag
import subprocess
out = subprocess.run(
    ["docker", "exec", "l6-prom", "wget", "-qO-",
     "http://localhost:9090/api/v1/status/flags"],
    capture_output=True, text=True).stdout
import json
flags = json.loads(out)["data"]
for k in ["query.max-samples", "query.max-concurrency", "query.timeout",
          "query.lookback-delta"]:
    print(f"   {k} = {flags.get(k)}")

print()
print("== 3. 单次裸查询前后各查一次（不等抓取，看是否即时累加） ==")
end = now()
for label, expr, s, e, st in [
    ("瞬时 l6_requests_total", "l6_requests_total", None, None, None),
    ("区间 5m/15s", "l6_requests_total", end - 300, end, "15s"),
    ("区间 60m/15s", "l6_requests_total", end - 3600, end, "15s"),
]:
    b = query("sum(prometheus_engine_query_samples_total)")
    if s:
        query_range(expr, s, e, st)
    else:
        query(expr)
    a = query("sum(prometheus_engine_query_samples_total)")
    bv = float(b[0]["value"][1]) if b else 0
    av = float(a[0]["value"][1]) if a else 0
    print(f"   {label:<24} before={bv:.0f} after={av:.0f} delta={av-bv:.0f}")
    time.sleep(1)

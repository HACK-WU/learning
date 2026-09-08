"""E1 预研：v3.14.0 的查询统计 API 到底能给出什么。

目的：找到能"量化查询成本"的官方指标，而不是只看墙钟耗时。
"""
import json
import time

from l6lib import PROM, _wget, query, app_get

print("== 0. 环境自检 ==")
print("app health:", app_get("/health"))
r = query("l6_requests_total")
print("l6_requests_total 序列数:", len(r) if r else "None")

print()
print("== 1. 探测 /api/v1/status/tsdb 的查询相关字段 ==")
out = _wget("/api/v1/status/tsdb")
try:
    d = json.loads(out)["data"]
    for k in sorted(d.keys()):
        print(f"  {k}: {str(d[k])[:80]}")
except Exception as e:
    print("  parse fail:", e, out[:200])

print()
print("== 2. 探测 Prometheus 自身的查询耗时指标 ==")
# 官方提供 prometheus_engine_query_duration_seconds（直方图）
for metric in [
    "prometheus_engine_query_duration_seconds_count",
    "prometheus_engine_query_samples_total",
    "prometheus_engine_query_samples_total_count",
]:
    r = query(metric)
    print(f"  {metric}: {len(r) if r else 0} 条")
    if r:
        for s in r[:5]:
            print("    ", s["metric"], "=", s["value"][1])

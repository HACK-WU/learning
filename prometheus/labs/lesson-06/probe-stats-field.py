"""诊断：单次查询的成本到底能从哪里读到？

候选：
1. /api/v1/query 的 stats 字段（需 stats=all 参数）
2. 引擎直方图 prometheus_engine_query_duration_seconds（按 slice 分）
3. prometheus_engine_query_samples（gauge，不是 counter）
"""
import json

from l6lib import _wget, query, now

print("== 1. 带 stats=all 的查询响应 ==")
q = "l6_requests_total"
url = f"/api/v1/query?query={q}&stats=all"
out = _wget(url)
try:
    d = json.loads(out)
    print("   status:", d.get("status"))
    print("   stats:", json.dumps(d.get("stats"), indent=2, ensure_ascii=False))
except Exception as e:
    print("   parse fail:", e, out[:300])

print()
print("== 2. 引擎直方图：各 slice 的语义 ==")
r = query("prometheus_engine_query_duration_seconds_count")
for s in r or []:
    print(f'   slice={s["metric"].get("slice"):<14} count={s["value"][1]}')

print()
print("== 3. 是否存在 gauge 版的当前查询样本数 ==")
for m in ["prometheus_engine_query_samples",
          "prometheus_engine_query_samples_seconds_total"]:
    r = query(m)
    print(f"   {m}: {len(r) if r else 0} 条")

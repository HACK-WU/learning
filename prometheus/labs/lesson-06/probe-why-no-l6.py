"""诊断：为什么 l6_requests_total 查不到？"""
from l6lib import app_get, query, _wget

print("== 1. app 直接返回什么 ==")
out = app_get("/metrics")
print(out)

print()
print("== 2. Prometheus 侧：所有 l6_ 开头的指标名 ==")
r = query('{__name__=~"l6_.*"}')
print("命中序列数:", len(r) if r else "None")
if r:
    seen = {}
    for s in r:
        seen[s["metric"]["__name__"]] = seen.get(s["metric"]["__name__"], 0) + 1
    for k, v in sorted(seen.items()):
        print(f"  {k}: {v} 条")

print()
print("== 3. Target 健康状态 ==")
import json
d = json.loads(_wget("/api/v1/targets?state=active"))
for t in d["data"]["activeTargets"]:
    print(f'  job={t["labels"].get("job")} health={t.get("health")} '
          f'lastError="{t.get("lastError","")}"')

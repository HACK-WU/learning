#!/usr/bin/env python3
"""诊断：全局节点上 l8_requests_total 是否存在、有几个样本、rate 能否算"""
import json
import subprocess
import time
import urllib.parse


def get(port, path, params):
    url = f"http://localhost:{port}{path}?" + urllib.parse.urlencode(params)
    r = subprocess.run(["curl", "-s", url], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:400]}


print("=== 1. 全局节点上有哪些 l8_ 指标名 ===")
d = get(19114, "/api/v1/query", {"query": 'count by(__name__) ({__name__=~"l8_.*"})'})
for s in d.get("data", {}).get("result", []):
    print(f"   {s['metric'].get('__name__')}: {s['value'][1]}")

print()
print("=== 2. l8_requests_total 在全局节点上的原始值 ===")
d = get(19114, "/api/v1/query", {"query": 'l8_requests_total'})
res = d.get("data", {}).get("result", [])
print(f"   命中 {len(res)} 条")
for s in res[:6]:
    print(f"   {s['metric']} = {s['value'][1]}")

print()
print("=== 3. 直接算 rate（2分钟窗口） ===")
d = get(19114, "/api/v1/query", {"query": 'rate(l8_requests_total[2m])'})
res = d.get("data", {}).get("result", [])
print(f"   rate 命中 {len(res)} 条")
for s in res[:4]:
    print(f"   {s['metric']} = {s['value'][1]}")
if not res:
    print(f"   warnings = {d.get('warnings')}")

print()
print("=== 4. 全局节点上 l8_requests_total 的时间序列密度（最近2分钟，15s步长） ===")
now = time.time()
d = get(19114, "/api/v1/query_range", {
    "query": 'l8_requests_total{method="GET",cluster="leaf-a"}',
    "start": now - 120, "end": now, "step": "15s",
})
res = d.get("data", {}).get("result", [])
print(f"   返回 {len(res)} 条序列")
if res:
    ts = res[0]["values"]
    print(f"   样本点数 = {len(ts)}（15s 步长 × 120s 应约 8 点）")
    for t, v in ts[:10]:
        print(f"     {t} -> {v}")

print()
print("=== 5. 叶子节点对照（同样 2 分钟 15s 步长） ===")
d = get(19110, "/api/v1/query_range", {
    "query": 'l8_requests_total{method="GET"}',
    "start": now - 120, "end": now, "step": "15s",
})
res = d.get("data", {}).get("result", [])
if res:
    print(f"   样本点数 = {len(res[0]['values'])}")
    for t, v in res[0]["values"][:10]:
        print(f"     {t} -> {v}")

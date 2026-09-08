#!/usr/bin/env python3
"""知识点 1 决定性对照：
1. federate 输出的 TYPE 全是 untyped —— 验证对 counter 的影响（rate 是否还能算）
2. honor_labels: true / false 的标签差异（决定性）
3. 联邦只传瞬时值 —— 验证 rate() 在联邦数据上是否失真
"""
import json
import subprocess
import sys
import time
import urllib.parse

LEAF_A = "http://localhost:19110"
LEAF_B = "http://localhost:19111"
GLOBAL = "http://localhost:19114"
VM = "http://localhost:19115"


def q(base, expr):
    url = base + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    out = subprocess.run(
        ["docker", "exec", "l8-global", "wget", "-qO-", url],
        capture_output=True, text=True,
    )
    try:
        data = json.loads(out.stdout)
        return data["data"]["result"]
    except Exception:
        return None


def q_local(port, expr):
    url = f"http://localhost:{port}/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    out = subprocess.run(["curl", "-s", url], capture_output=True, text=True)
    data = json.loads(out.stdout)
    return data["data"]["result"]


def federate(port, match, limit=None):
    url = f"http://localhost:{port}/federate?" + urllib.parse.urlencode({"match[]": match})
    out = subprocess.run(["curl", "-s", url], capture_output=True, text=True)
    lines = [l for l in out.stdout.split("\n") if l and not l.startswith("# HELP")]
    if limit:
        lines = lines[:limit]
    return out.stdout, lines


print("=" * 70)
print("E1: federate 输出的 TYPE —— 验证 counter 的类型是否丢失")
print("=" * 70)
raw, lines = federate(19110, '{__name__="l8_requests_total"}')
for l in lines:
    if l.startswith("# TYPE"):
        print(f"  {l}")
print("  --> 结论：counter 在 federate 输出中变成 untyped")

print()
print("=" * 70)
print("E1b: 类型丢失的实际影响 —— 在全局节点上算 rate()")
print("=" * 70)
# 先让数据积累
print("  等待 30 秒让 counter 积累样本...")
time.sleep(30)

leaf_rate = q_local(19110, 'rate(l8_requests_total{method="GET"}[2m])')
print(f"  叶子本地 rate(l8_requests_total[2m])  = {leaf_rate[0]['value'][1] if leaf_rate else 'N/A'}")

glob_rate = q(GLOBAL, 'rate(l8_requests_total{method="GET",cluster="leaf-a"}[2m])')
print(f"  全局联邦 rate(...[2m])                = {glob_rate[0]['value'][1] if glob_rate else 'N/A'}")

print()
print("=" * 70)
print("E2: honor_labels 决定性对照")
print("=" * 70)
print("  当前全局节点配置 honor_labels: true")
r = q(GLOBAL, 'l8_card_balance{idx="0001"}')
print(f"  命中 {len(r)} 条")
for s in r:
    m = s["metric"]
    print(f"    cluster={m.get('cluster')}  job={m.get('job')}  "
          f"instance={m.get('instance')}  source_cluster={m.get('source_cluster')}")

print()
print("  注意 job/instance：")
for s in r:
    m = s["metric"]
    print(f"    job={m.get('job')!r} instance={m.get('instance')!r}  "
          f"<- 若 honor_labels=false，这两个会被改写成联邦 target 的 job/instance")

print()
print("=" * 70)
print("E3: 联邦只传瞬时值 —— 全局节点的样本密度 vs 叶子")
print("=" * 70)
for name, port, expr in [
    ("叶子 leaf-a", 19110, 'l8_card_balance{idx="0001"}'),
    ("全局（联邦）", 19114, 'l8_card_balance{idx="0001",cluster="leaf-a"}'),
]:
    url = f"http://localhost:{port}/api/v1/query_range?" + urllib.parse.urlencode({
        "query": expr, "start": time.time() - 120, "end": time.time(), "step": "5s",
    })
    out = subprocess.run(["curl", "-s", url], capture_output=True, text=True)
    data = json.loads(out.stdout)
    res = data["data"]["result"]
    n = len(res[0]["values"]) if res else 0
    print(f"  {name:14s} 2 分钟内 5s 步长应有 24 点，实际 {n} 点")

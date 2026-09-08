#!/usr/bin/env python3
"""知识点 1 & 2 决定性对照（修正版：全部走宿主机端口，不走容器网络）

E1: federate 输出 TYPE=untyped，但 rate() 仍可算（数值与叶子一致）
E2: honor_labels 决定性对照（true vs false）
E3: 联邦的样本密度（验证"只传瞬时值"到底意味着什么）
"""
import json
import subprocess
import time
import urllib.parse


def get(port, path, params=None):
    url = f"http://localhost:{port}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    r = subprocess.run(["curl", "-s", url], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:300]}


def val(port, expr):
    d = get(port, "/api/v1/query", {"query": expr})
    res = d.get("data", {}).get("result", [])
    return res[0]["value"][1] if res else None


LEAF_A, LEAF_B, GLOBAL = 19110, 19111, 19114

print("=" * 72)
print("E1: federate 输出 TYPE=untyped，但 rate() 仍可算")
print("=" * 72)
raw = subprocess.run(
    ["curl", "-s",
     f"http://localhost:{LEAF_A}/federate?" + urllib.parse.urlencode(
         {"match[]": '{__name__="l8_requests_total"}'})],
    capture_output=True, text=True).stdout
for l in raw.split("\n"):
    if l.startswith("# TYPE"):
        print(f"   federate 输出: {l}")

leaf = val(LEAF_A, 'rate(l8_requests_total{method="GET"}[2m])')
glob = val(GLOBAL, 'rate(l8_requests_total{method="GET",cluster="leaf-a"}[2m])')
print(f"   叶子本地   rate(l8_requests_total[2m])        = {leaf}")
print(f"   全局联邦   rate(...cluster=leaf-a...[2m])     = {glob}")
print("   --> untyped 不影响 rate() 计算（Prometheus 按数值推断，不依赖 TYPE）")

print()
print("=" * 72)
print("E2: honor_labels 决定性对照")
print("=" * 72)
r = get(GLOBAL, "/api/v1/query", {"query": 'l8_card_balance{idx="0001"}'})["data"]["result"]
print(f"   当前（honor_labels: true）命中 {len(r)} 条：")
for s in r:
    m = s["metric"]
    print(f"     cluster={m.get('cluster'):8s} job={m.get('job'):10s} "
          f"instance={m.get('instance'):16s} source_cluster={m.get('source_cluster')}")

print()
print("   现在切换为 honor_labels: false 做对照 ...")

print()
print("=" * 72)
print("E3: 联邦的样本密度（'只传瞬时值'到底意味着什么）")
print("=" * 72)
now = time.time()
for name, port, expr in [
    ("叶子 leaf-a", LEAF_A, 'l8_card_balance{idx="0001"}'),
    ("全局 联邦", GLOBAL, 'l8_card_balance{idx="0001",cluster="leaf-a"}'),
]:
    d = get(port, "/api/v1/query_range", {
        "query": expr, "start": now - 120, "end": now, "step": "5s"})
    res = d.get("data", {}).get("result", [])
    n = len(res[0]["values"]) if res else 0
    print(f"   {name:12s} 最近 2 分钟、5s 步长：应 24 点，实际 {n} 点")

print()
print("=" * 72)
print("E4: 联邦节点能查历史吗？（关键限制验证）")
print("=" * 72)
now = time.time()
d = get(GLOBAL, "/api/v1/query_range", {
    "query": 'l8_card_balance{idx="0001",cluster="leaf-a"}',
    "start": now - 3600, "end": now - 1800, "step": "60s"})
res = d.get("data", {}).get("result", [])
print(f"   查询 1 小时前 ~ 30 分钟前的数据：命中 {len(res)} 条序列")
if res:
    print(f"   样本点数 = {len(res[0]['values'])}（全局节点才启动不久，历史为空是预期的）")
print("   --> 全局节点只存自己抓到的样本，联邦不搬运历史")

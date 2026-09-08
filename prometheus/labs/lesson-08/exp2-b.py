#!/usr/bin/env python3
"""决定性：honor_labels=false 时两个叶子抓同一个 app 的标签结果
（修正：全部用 curl -G --data-urlencode，不手工编码）
"""
import json
import subprocess


def q(port, expr):
    out = subprocess.run(
        ["curl", "-s", "-G", f"http://localhost:{port}/api/v1/query",
         "--data-urlencode", f"query={expr}"],
        capture_output=True, text=True)
    try:
        return json.loads(out.stdout)["data"]["result"]
    except Exception as e:
        print(f"   [ERR] {e}: {out.stdout[:200]}")
        return []


print("=" * 72)
print("场景：两个叶子抓同一个 app（instance 都是 l8-app:8080）")
print("=" * 72)

for label, port in [("honor_labels=true ", 19114), ("honor_labels=false", 19116)]:
    r = q(port, "l8_card_balance")
    print(f"\n  --- {label} ---")
    print(f"  l8_card_balance 总条数 = {len(r)}  （每叶子 500 条，两叶子应 1000）")
    inst = {}
    for s in r:
        k = (s["metric"].get("cluster"), s["metric"].get("job"), s["metric"].get("instance"))
        inst[k] = inst.get(k, 0) + 1
    for k, v in sorted(inst.items(), key=lambda x: -x[1])[:6]:
        print(f"     cluster={str(k[0]):8s} job={str(k[1]):16s} instance={str(k[2]):18s} -> {v} 条")

print()
print("=" * 72)
print("关键对照：不带 cluster 标签时，两侧各能查到几条？")
print("=" * 72)
for label, port in [("honor_labels=true ", 19114), ("honor_labels=false", 19116)]:
    r = q(port, 'l8_card_balance{idx="0001"}')
    print(f"  {label}: l8_card_balance{{idx=0001}} 命中 {len(r)} 条")

print()
print("=" * 72)
print("决定性：honor_labels=true 时，若去掉 external_labels 的 cluster 会怎样")
print("=" * 72)
r = q(19114, 'count by (cluster) (l8_card_balance)')
print("  全局节点上按 cluster 分组：")
for s in r:
    print(f"     cluster={s['metric'].get('cluster')} -> {s['value'][1]} 条")
print()
print("  若两叶子 external_labels 相同（都叫 prod），这两组会合并成一组 1000 条，")
print("  而它们实际是两份独立采集的、值不相等的数据 -> 查询结果随机跳变")

#!/usr/bin/env python3
"""知识点 2：HA 双写与数据一致性

E1: 两个副本抓同一 target，各自存一份，互不知情
E2: 副本间数据不一致（抓取时刻不同）导致查询结果跳变 —— 决定性
E3: 去重在哪做？Prometheus 自己不做（它压根不知道对方存在）
E4: 后端（VM）收到两份数据，dedup 前后对比
"""
import json
import subprocess
import time
import urllib.parse


def q(port, expr, host="localhost"):
    out = subprocess.run(
        ["curl", "-s", "-G", f"http://{host}:{port}/api/v1/query",
         "--data-urlencode", f"query={expr}"],
        capture_output=True, text=True)
    try:
        return json.loads(out.stdout)["data"]["result"]
    except Exception:
        return []


R1, R2, VM = 19112, 19113, 19115

print("=" * 72)
print("E1: 两个副本抓同一 target，各自存一份，互不知情")
print("=" * 72)
for name, port in [("replica-1", R1), ("replica-2", R2)]:
    r = q(port, 'up{job="l8-app"}')
    n = q(port, "count(l8_card_balance)")
    print(f"   {name}: up={r[0]['value'][1] if r else 'N/A'}  "
          f"l8_card_balance={n[0]['value'][1] if n else 'N/A'} 条")
print("   --> 两个副本各自独立采集，互不感知")

print()
print("=" * 72)
print("E2: 副本间数据不一致 —— 同一时刻查同一条序列，两边值不同")
print("=" * 72)
print("   连续采样 6 次（间隔 2s），对比 replica-1 与 replica-2 的值：")
print(f"   {'时刻':>8s}  {'replica-1':>14s}  {'replica-2':>14s}  {'差值':>12s}")
diffs = []
for i in range(6):
    v1 = q(R1, 'l8_card_balance{idx="0001"}')
    v2 = q(R2, 'l8_card_balance{idx="0001"}')
    if v1 and v2:
        a, b = float(v1[0]["value"][1]), float(v2[0]["value"][1])
        diffs.append(abs(a - b))
        print(f"   #{i+1:<7d} {a:14.2f}  {b:14.2f}  {abs(a-b):12.2f}")
    time.sleep(2)

if diffs:
    print(f"\n   平均差值 = {sum(diffs)/len(diffs):.2f}，最大 = {max(diffs):.2f}")
    print("   --> 两个副本抓的是同一条序列，但因为抓取时刻不同，值永远不相等")

print()
print("=" * 72)
print("E3: Prometheus 自己会去重吗？（决定性）")
print("=" * 72)
r = q(R1, "count(l8_card_balance)")
print(f"   replica-1 本地 l8_card_balance = {r[0]['value'][1] if r else 'N/A'} 条")
print("   replica-1 只知道自己抓的 500 条，不知道 replica-2 的存在")
print("   --> 去重不可能在 Prometheus 侧发生")

print()
print("=" * 72)
print("E4: 后端（VM）收到两份数据 —— 去重前后对比")
print("=" * 72)
# VM 上按 replica 分组
for expr, desc in [
    ('count(l8_card_balance)', "不去重，总数"),
    ('count by (replica) (l8_card_balance)', "按 replica 分组"),
    ('count(l8_card_balance{replica="1"})', "只看 replica=1"),
    ('count(l8_card_balance{replica="2"})', "只看 replica=2"),
]:
    r = q(VM, expr)
    if r:
        vals = [(s["metric"].get("replica", "-"), s["value"][1]) for s in r]
        print(f"   {desc:24s} -> {vals}")
    else:
        print(f"   {desc:24s} -> 0 条")

print()
print("   --- VM 去重（dedup.minScrapeInterval=1s）后的效果 ---")
r = q(VM, 'count(l8_card_balance)')
print(f"   去重后总数（不带 replica 标签查询）= {r[0]['value'][1] if r else 'N/A'}")

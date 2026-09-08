#!/usr/bin/env python3
"""
E5b：remote read 真正跑通（后端换成原生支持 remote read 的 Prometheus）

架构：
  l7-backend (19105)  抓取 l7-app，本地存 500 条 l7_card_balance，开启 receiver
  l7-reader  (19106)  只抓自己，本地【没有】l7_card_balance，靠 remote read 取

判据：
  reader 能查到 l7_card_balance → remote read 生效
  reader 查不到                → remote read 未生效

同时观察：
  - warnings 字段（remote read 失败会静默写在这里）
  - 耗时对照：本地查询 vs remote read 查询
"""
import json
import time
import urllib.parse
import urllib.request

READER = "http://localhost:19106"
BACKEND = "http://localhost:19105"


def raw_query(host, q, qrange=None):
    """返回原始 JSON，保留 warnings 字段。"""
    if qrange:
        s, e, st = qrange
        url = (f"{host}/api/v1/query_range?query={urllib.parse.quote(q)}"
               f"&start={s}&end={e}&step={st}")
    else:
        url = f"{host}/api/v1/query?query={urllib.parse.quote(q)}"
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.loads(r.read().decode())


def show(host, q, label, qrange=None):
    d = raw_query(host, q, qrange)
    res = d.get("data", {}).get("result", [])
    warn = d.get("warnings", [])
    npts = sum(len(s.get("values", [])) for s in res) if qrange else len(res)
    print(f"  {label:34s} 结果={len(res):>4d}序列/{npts:>6d}点")
    if warn:
        for w in warn:
            print(f"      ⚠ warning: {w[:110]}")
    return len(res), npts, warn


print("=" * 78)
print("E5b  remote read 生效验证（后端 = Prometheus，原生支持）")
print("=" * 78)

print("\n[1] 前提确认：两边本地数据是否不对称")
show(BACKEND, "l7_card_balance", "backend 本地查（应=500）")
show(READER, "l7_card_balance", "reader 查（本地无，应靠远端）")

print("\n[2] 决定性判据：reader 本地真的没有这批数据吗？")
print("    查 reader 的 target 列表里有没有 l7-app")
d = raw_query(READER, "up")
for s in d.get("data", {}).get("result", []):
    print(f"      up{ {k:v for k,v in s['metric'].items() if k!='__name__'} }")

print("\n[3] 如果 reader 能查到 500，说明 remote read 生效")
n, _, w = show(READER, "l7_card_balance", "reader 最终查询结果")
if n == 500 and not w:
    print("\n  >>> remote read 生效：reader 本地无数据，却查到了 500 条")
elif n == 500 and w:
    print("\n  >>> 查到 500 条，但有 warning，需确认是否来自本地还是远端")
else:
    print("\n  >>> remote read 未生效或数据不完整")

print("\n[4] 范围查询对照（这才是 remote read 的典型用法）")
now = time.time()
for span, label in ((300, "5分钟(本地窗口内)"), (3600, "1小时"), (7200, "2小时")):
    s = now - span
    n_b, p_b, w_b = show(BACKEND, "l7_card_balance", f"backend  {label}",
                         qrange=(s, now, 60))
    n_r, p_r, w_r = show(READER, "l7_card_balance", f"reader   {label}",
                         qrange=(s, now, 60))
    print()

print("[5] 耗时对照：同一个范围查询，本地 vs remote read")
from l7lib import timing

def t_backend():
    raw_query(BACKEND, "l7_card_balance", qrange=(now - 3600, now, 60))


def t_reader():
    raw_query(READER, "l7_card_balance", qrange=(now - 3600, now, 60))


tb = timing(t_backend, n=5)
tr = timing(t_reader, n=5)
print(f"    {'目标':16s} {'中位':>10s} {'最小':>10s} {'最大':>10s}")
print(f"    {'backend(本地)':16s} {tb['med']:>8.1f}ms {tb['min']:>8.1f}ms {tb['max']:>8.1f}ms")
print(f"    {'reader(远端)':16s} {tr['med']:>8.1f}ms {tr['min']:>8.1f}ms {tr['max']:>8.1f}ms")
if tb["med"]:
    print(f"    → remote read / 本地 = {tr['med']/tb['med']:.2f}x")

print("\n" + "=" * 78)
print("E5b 小结")
print("=" * 78)

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 4 · 知识点 4.2 探测（第一部分，不依赖抓包）
Q1: 前端调 /api/ds/query 时，请求里到底带了哪些「旅程控制参数」？
Q2: 后端回传的 meta 里，哪些字段能反证「后端做了什么」？
    - executedQueryString（最终发给 Prometheus 的表达式 + step）
    - calculatedMinStep（后端算出的步长）
    - searchWords（Grafana 12+ 新增，反证后端的表达式理解）
Q3: maxDataPoints / intervalMs 变化时，calculatedMinStep 如何响应？
    → 证明「后端会自作主张改你的参数」
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"


def req(method, path, body=None, timeout=60):
    url = GF + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Basic " + AUTH)
    r.add_header("Content-Type", "application/json")
    r.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw or "{}")
        except Exception:
            return e.code, {"_raw": raw[:400]}


def query(expr, intervalMs=15000, maxDataPoints=100, frm="now-1h", to="now", extra=None):
    q = {
        "refId": "A",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "expr": expr, "range": True, "instant": False,
        "intervalMs": intervalMs, "maxDataPoints": maxDataPoints,
    }
    if extra:
        q.update(extra)
    return req("POST", "/api/ds/query",
               {"queries": [q], "from": frm, "to": to}, timeout=90)


print("=" * 76)
print(" 4.2 探测（一）：旅程控制参数与后端自作主张")
print("=" * 76)

EXPR = 'rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])'

print("\n--- [Q1] 请求里带什么（我们发出的 payload） ---\n")
sample = {
    "refId": "A",
    "datasource": {"type": "prometheus", "uid": DS_UID},
    "expr": EXPR, "range": True, "instant": False,
    "intervalMs": 15000, "maxDataPoints": 100,
}
print(json.dumps({"queries": [sample], "from": "now-1h", "to": "now"},
                 indent=2, ensure_ascii=False))

print("\n--- [Q2] 后端回传的 meta（能反证后端做了什么） ---\n")
st, body = query(EXPR)
res = body["results"]["A"]
fr = res["frames"][0]
meta = fr["schema"]["meta"]
print("results.A 顶层字段：%s" % ", ".join(sorted(res.keys())))
print("frame 字段        ：%s" % ", ".join(sorted(fr.keys())))
print("meta 全部字段     ：%s" % ", ".join(sorted(meta.keys())))
print()
print("meta 全文：")
print(json.dumps(meta, indent=2, ensure_ascii=False))

print("\n--- [Q2b] 各 meta 字段含义对照（逐字段打印） ---\n")
for k in sorted(meta.keys()):
    v = meta[k]
    print("  %-24s = %s" % (k, json.dumps(v, ensure_ascii=False)[:100]))

print("\n--- [Q3] 调 maxDataPoints / intervalMs，看 calculatedMinStep 响应 ---\n")
print("%-14s %-10s %-18s %-12s %s" % (
    "intervalMs", "maxDP", "calculatedMinStep", "实际点数", "executedQueryString 的 Step"))
print("-" * 76)

cases = [
    (15000, 100),
    (1000, 100),
    (60000, 100),
    (15000, 10),
    (15000, 1000),
    (15000, 2000),
]
rows = []
for ims, mdp in cases:
    st, body = query(EXPR, intervalMs=ims, maxDataPoints=mdp)
    res = body.get("results", {}).get("A") or {}
    frs = res.get("frames") or []
    if not frs:
        print("%-14s %-10s (无 frame)" % (ims, mdp))
        continue
    m = frs[0]["schema"]["meta"]
    custom = m.get("custom") or {}
    step = custom.get("calculatedMinStep", "-")
    vals = frs[0]["data"]["values"]
    npts = len(vals[0]) if vals else 0
    eqs = m.get("executedQueryString", "")
    step_line = ""
    for line in eqs.split("\n"):
        if line.startswith("Step:"):
            step_line = line.strip()
    rows.append((ims, mdp, step, npts))
    print("%-14s %-10s %-18s %-12s %s" % (ims, mdp, step, npts, step_line or "-"))

print("\n--- [Q3b] 时间窗口对步长的影响（面板宽度不变，只改窗口） ---\n")
print("%-12s %-18s %-12s %s" % ("时间窗口", "calculatedMinStep", "实际点数", "Step 行"))
print("-" * 76)
for win in ("now-5m", "now-15m", "now-1h", "now-6h", "now-24h"):
    st, body = query(EXPR, frm=win)
    res = body.get("results", {}).get("A") or {}
    frs = res.get("frames") or []
    if not frs:
        print("%-12s (无 frame)" % win)
        continue
    m = frs[0]["schema"]["meta"]
    step = (m.get("custom") or {}).get("calculatedMinStep", "-")
    vals = frs[0]["data"]["values"]
    npts = len(vals[0]) if vals else 0
    eqs = m.get("executedQueryString", "")
    step_line = [l.strip() for l in eqs.split("\n") if l.startswith("Step:")]
    print("%-12s %-18s %-12s %s" % (win, step, npts, step_line[0] if step_line else "-"))

print("\n--- [Q4] $__rate_interval 在 executedQueryString 里长什么样 ---\n")
st, body = query(EXPR, intervalMs=15000, maxDataPoints=100)
m = body["results"]["A"]["frames"][0]["schema"]["meta"]
print("executedQueryString 全文：")
print(m.get("executedQueryString", "(无此字段)"))

print("\n--- [Q5] 对比：直接查 Prometheus，同样窗口算出的点数 ---\n")
import urllib.request as u2
try:
    with u2.urlopen("http://localhost:9201/api/v1/query?query=up", timeout=20) as r:
        d = json.loads(r.read().decode())
        print("  Prometheus 直查 up -> status=%s, 结果数=%s" % (
            d.get("status"), len(d.get("data", {}).get("result", []))))
except Exception as e:
    print("  直查失败：%s" % e)

print("\n" + "=" * 76)

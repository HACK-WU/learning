#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 4 · 知识点 4.2 探测（第二部分）
Q1: 四层定位矩阵——同一个「图不对」，在四层的表现分别是什么？
    L1 浏览器→Grafana 前端   L2 前端→Grafana 后端
    L3 Grafana 后端→数据源   L4 数据源→存储引擎
Q2: Inspector 的四个页签（Stats/Query/JSON/Data）各自对应哪一层？
Q3: 四种典型故障在各层的可观测性（能不能看见？在哪看见？）
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
GOOD = "afx7x6dx803y8e"


def req(method, path, body=None, timeout=90):
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


def query(uid, expr, extra=None, frm="now-1h", to="now"):
    q = {"refId": "A", "datasource": {"type": "prometheus", "uid": uid},
         "expr": expr, "range": True, "instant": False,
         "intervalMs": 15000, "maxDataPoints": 100}
    if extra:
        q.update(extra)
    return req("POST", "/api/ds/query", {"queries": [q], "from": frm, "to": to})


print("=" * 78)
print(" 4.2 探测（二）：四层定位矩阵 —— 各层能看到什么")
print("=" * 78)

# 建故障数据源
print("\n--- [准备] 故障数据源 ---")
for nm, uid, url in [("L04Dead2", "l04dead2", "http://grafana-prom:9999")]:
    req("DELETE", "/api/datasources/uid/" + uid)
    st, _ = req("POST", "/api/datasources", {
        "name": nm, "uid": uid, "type": "prometheus", "access": "proxy",
        "url": url, "isDefault": False, "jsonData": {"httpMethod": "POST"}})
    print("  %s -> HTTP %s" % (nm, st))

print("\n--- [Q1] 四层观测：同一查询，各层留下了什么痕迹 ---\n")

# L2 层：前端→后端，我们发的是什么
q_payload = {"queries": [{
    "refId": "A", "datasource": {"type": "prometheus", "uid": GOOD},
    "expr": "up", "range": True, "instant": False,
    "intervalMs": 15000, "maxDataPoints": 100}],
    "from": "now-1h", "to": "now"}
print("[L2 请求] 浏览器/前端 → Grafana 后端")
print("  路径：POST /api/ds/query")
print("  Content-Type: application/json")
print("  body：%s" % json.dumps(q_payload, ensure_ascii=False)[:130])

st, body = query(GOOD, "up")
res = body["results"]["A"]
print("\n[L2 响应] Grafana 后端 → 前端")
print("  外层 HTTP：%s" % st)
print("  body 顶层字段：%s" % ", ".join(sorted(body.keys())))
print("  results.A 字段：%s" % ", ".join(sorted(res.keys())))

print("\n[L3 痕迹] 后端 → Prometheus（由 executedQueryString 反证）")
m = res["frames"][0]["schema"]["meta"]
print("  %s" % m.get("executedQueryString", "-").replace("\n", " | "))

print("\n[L1 痕迹] 浏览器侧（Inspector 的 Stats 页签）")
print("  浏览器 DevTools Network 能看到：")
print("    - /api/ds/query 的状态码、耗时、请求/响应体")
print("    - 但看不到 L3（后端→数据源）的任何信息")

print("\n--- [Q2] Inspector 四页签 ↔ 层级对应 ---\n")
print("%-14s %-24s %s" % ("Inspector 页签", "对应层", "内容"))
print("-" * 78)
rows = [
    ("Query", "L2（前端→后端）", "请求耗时、payload 大小、返回行数"),
    ("{} JSON", "L2/L3 交界", "完整 data frame（含 meta.executedQueryString）"),
    ("Data", "L3（后端→数据源）", "表格化展示，可导出 CSV"),
    ("Stats", "L1（浏览器侧）", "渲染耗时、数据点总数"),
]
for a, b, c in rows:
    print("%-14s %-24s %s" % (a, b, c))

print("\n  实证：从 results.A.frames[0].schema.meta 读到的，就是 Inspector 的 {} JSON：")
print("  " + json.dumps(m, ensure_ascii=False))

print("\n--- [Q3] 四种故障在各层的可观测性 ---\n")
cases = [
    ("后端不可达", "l04dead2", "up", {}),
    ("表达式语法错", GOOD, "up{", {}),
    ("指标名不存在", GOOD, "no_such_metric_xyz", {}),
    ("查询超时窗口", GOOD, "up", {}),
]
print("%-14s %-8s %-8s %-12s %-10s %s" % (
    "故障", "HTTP", "内层", "errorSource", "frames", "是否静默"))
print("-" * 78)
for label, uid, expr, extra in cases:
    st, body = query(uid, expr, extra)
    res = (body.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    npts = 0
    for f in frs:
        v = f.get("data", {}).get("values") or []
        if v:
            npts += len(v[0])
    inner = res.get("status", "-")
    src = res.get("errorSource", "-")
    err = res.get("error", "")
    silent = "是（图空白无报错）" if (st == 200 and npts == 0) else \
             ("否（面板报错）" if err else "否（有数据）")
    print("%-14s %-8s %-8s %-12s %-10s %s" % (label, st, inner, src, len(frs), silent))

print("\n--- [Q3b] 「静默失败」三种：同样图空白，成因完全不同 ---\n")
print("%-22s %-8s %-8s %-10s %s" % ("情形", "HTTP", "内层", "frames", "判断依据"))
print("-" * 78)
silents = [
    ("合法但无数据", GOOD, 'up{instance="no-such-zzz"}'),
    ("指标名不存在", GOOD, "no_such_metric_xyz"),
    ("时间窗内无数据", GOOD, "up"),
]
for label, uid, expr in silents:
    st, body = query(uid, expr)
    res = (body.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    print("%-22s %-8s %-8s %-10s %s" % (
        label, st, res.get("status", "-"), len(frs),
        (frs[0]["schema"]["meta"].get("executedQueryString", "-").split("\n")[0]
         if frs else "-")))

# 时间窗内无数据：用一个未来时间窗
print("\n  补充：把时间窗挪到未来（肯定无数据）")
st, body = query(GOOD, "up", frm="now+1h", to="now+2h")
res = (body.get("results") or {}).get("A") or {}
frs = res.get("frames") or []
npts = sum(len(f["data"]["values"][0]) for f in frs if f.get("data", {}).get("values"))
print("    HTTP=%s 内层=%s frames=%s 点数=%s" % (st, res.get("status"), len(frs), npts))

print("\n--- [Q4] 请求头里的身份信息（X-Grafana-Id） ---")
print("  L3 请求会带上 X-Grafana-Id（JWT），内含：")
print("    user:1 / login:admin / role:Admin / namespace:default")
print("  → 数据源侧可以据此做行级权限；也说明身份是逐跳透传的")

print("\n--- [清理] ---")
for uid in ("l04dead2",):
    st, _ = req("DELETE", "/api/datasources/uid/" + uid)
    print("  %s 删除 HTTP %s" % (uid, st))

print("\n" + "=" * 78)

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 4 · 知识点 4.3 探测
目标：复现「HTTP 400 里的 status 502」——外层 HTTP 状态码与 body 内真实错误码分离。
五种场景对照：正常 / 端口不通 / DNS 不可解析 / 语法错 / 无数据
"""
import json, urllib.request, urllib.error, base64, time

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
GOOD = "afx7x6dx803y8e"


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
            return e.code, {"_raw": raw[:600]}


def make_ds(name, uid, url):
    body = {
        "name": name, "uid": uid, "type": "prometheus", "access": "proxy",
        "url": url, "isDefault": False,
        "jsonData": {"httpMethod": "POST"},
    }
    st, r = req("POST", "/api/datasources", body)
    return st, r


def query(uid, expr):
    payload = {
        "queries": [{
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": uid},
            "expr": expr, "range": True, "instant": False,
            "intervalMs": 15000, "maxDataPoints": 100,
        }],
        "from": "now-1h", "to": "now",
    }
    return req("POST", "/api/ds/query", payload, timeout=90)


print("=" * 74)
print(" 4.3 探测：外层 HTTP 状态码 vs body 内的真实错误码")
print("=" * 74)

# 建两个坏数据源
print("\n--- [准备] 创建故障数据源 ---")
for nm, uid, url in [
    ("L04Dead", "l04dead", "http://grafana-prom:9999"),
    ("L04Ghost", "l04ghost", "http://no-such-host-xyz-404:9090"),
]:
    req("DELETE", "/api/datasources/uid/" + uid)
    st, r = make_ds(nm, uid, url)
    print("  %-9s url=%-38s 创建 HTTP %s" % (nm, url, st))

SCENES = [
    ("正常查询",       GOOD,     "up",                                  "基线"),
    ("后端端口不通",   "l04dead", "up",                                 "连接被拒"),
    ("后端 DNS 失败",  "l04ghost", "up",                                "无法解析"),
    ("查询语法错",     GOOD,     "up{",                                 "非法 PromQL"),
    ("查不到数据",     GOOD,     'up{instance="no-such-host-zzz"}',     "合法但空"),
]

print("\n--- [对照] 五种场景 ---\n")
print("%-14s %-6s %-9s %-12s %s" % ("场景", "HTTP", "body.status", "errorSource", "message 摘要"))
print("-" * 74)

details = {}
for label, uid, expr, note in SCENES:
    st, body = query(uid, expr)
    res = (body.get("results") or {}).get("A") or {}
    status = res.get("status", "-")
    src = res.get("errorSource", "-")
    err = res.get("error") or body.get("message") or "(无)"
    if "_raw" in body:
        err = body["_raw"][:80]
    frames = res.get("frames") or []
    npts = 0
    for f in frames:
        vals = f.get("data", {}).get("values") or []
        if vals:
            npts += len(vals[0])
    details[label] = {
        "http": st, "status": status, "src": src, "err": err,
        "frames": len(frames), "points": npts,
        "body_keys": sorted(body.keys()),
        "res_keys": sorted(res.keys()),
    }
    print("%-14s %-6s %-9s %-12s %s" % (label, st, status, src, str(err)[:60]))

print("\n--- [细看] 后端不可达时 body 的完整结构 ---\n")
st, body = query("l04dead", "up")
print("外层 HTTP 状态码：%s" % st)
print("body 顶层字段   ：%s" % ", ".join(sorted(body.keys())))
res = (body.get("results") or {}).get("A") or {}
print("results.A 字段  ：%s" % ", ".join(sorted(res.keys())))
print("results.A 全文  ：")
print(json.dumps(res, indent=2, ensure_ascii=False)[:1200])

print("\n--- [细看] 语法错时 body 的完整结构 ---\n")
st, body = query(GOOD, "up{")
print("外层 HTTP 状态码：%s" % st)
res = (body.get("results") or {}).get("A") or {}
print("results.A 全文  ：")
print(json.dumps(res, indent=2, ensure_ascii=False)[:1200])

print("\n--- [对照表] 三种错误的外层 vs 内层 ---\n")
print("%-14s %-8s %-8s %-14s %-10s %s" % ("场景", "HTTP", "内层", "errorSource", "frames", "点数"))
print("-" * 74)
for label, _, _, _ in SCENES:
    d = details[label]
    print("%-14s %-8s %-8s %-14s %-10s %s" % (
        label, d["http"], d["status"], d["src"], d["frames"], d["points"]))

# 清理
print("\n--- [清理] 删除故障数据源 ---")
for uid in ("l04dead", "l04ghost"):
    st, _ = req("DELETE", "/api/datasources/uid/" + uid)
    print("  %-9s 删除 HTTP %s" % (uid, st))

print("\n" + "=" * 74)

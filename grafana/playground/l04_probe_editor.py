#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 4 · 知识点 4.1 探测
Q1: editorMode 字段在 API 层是否可见、是否被保留？
Q2: 后端保存时会不会因 editorMode 改写 expr？
Q3: editorMode="explain" 是否被接受（Explain 到底是不是第三种模式）？
"""
import json, urllib.request, urllib.error, base64, sys

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
DASH_UID = "l04-editor-probe"


def req(method, path, body=None):
    url = GF + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Basic " + AUTH)
    r.add_header("Content-Type", "application/json")
    r.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw or "{}")
        except Exception:
            return e.code, {"_raw": raw[:400]}


def save(expr, mode):
    dash = {
        "uid": DASH_UID,
        "title": "L04 editorMode probe",
        "schemaVersion": 41,
        "panels": [{
            "id": 1, "type": "timeseries", "title": "p1",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "datasource": {"type": "prometheus", "uid": DS_UID},
            "targets": [{
                "refId": "A",
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "expr": expr,
                "editorMode": mode,
            }],
        }],
        "time": {"from": "now-1h", "to": "now"},
    }
    st, body = req("POST", "/api/dashboards/db", {"dashboard": dash, "overwrite": True})
    return st, body


def load():
    st, body = req("GET", "/api/dashboards/uid/" + DASH_UID)
    if st != 200:
        return None
    t = body["dashboard"]["panels"][0]["targets"][0]
    return t


print("=" * 66)
print(" 4.1 探测：editorMode 在 API 层的可见性与改写行为")
print("=" * 66)

EXPRS = [
    ("最简", "up"),
    ("带 label", 'up{job="node"}'),
    ("聚合+函数", 'sum(rate(node_cpu_seconds_total[5m])) by (instance)'),
    ("带宏", 'rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])'),
    ("复杂 unless", 'up{job="node"} unless on(instance) up{job="prometheus"}'),
]

print("\n--- [Q1+Q2] 同一 expr 分别以 code / builder 存，读回看是否被改写 ---\n")
print("%-14s %-9s %-9s %s" % ("表达式", "mode", "回读 mode", "expr 是否变化"))
print("-" * 66)

for label, expr in EXPRS:
    for mode in ("code", "builder"):
        st, _ = save(expr, mode)
        if st != 200:
            print("%-14s %-9s 保存失败 HTTP %s" % (label, mode, st))
            continue
        t = load()
        back_mode = t.get("editorMode", "(缺失)")
        back_expr = t.get("expr", "")
        changed = "否（expr 原样）" if back_expr == expr else "是 -> %s" % back_expr
        print("%-14s %-9s %-9s %s" % (label, mode, back_mode, changed))

print("\n--- [Q3] editorMode 取值探测：explain 是否被当作一种模式 ---\n")
for mode in ("code", "builder", "explain", "bogus-mode"):
    st, _ = save("up", mode)
    t = load()
    back = t.get("editorMode", "(缺失/被丢弃)")
    verdict = "被原样保留" if back == mode else "被改写/丢弃 -> %s" % back
    print("  写入 editorMode=%-12s 读回=%-14s %s" % (mode, back, verdict))

print("\n--- [附] 完整 target 结构（最后一次保存的回读） ---\n")
t = load()
print(json.dumps(t, indent=2, ensure_ascii=False))

print("\n--- [Q2 补充] builder 模式下 target 是否多出 visualQuery 类字段 ---\n")
save("up", "builder")
t = load()
keys = sorted(t.keys())
print("  builder 模式 target 字段：%s" % ", ".join(keys))
save("up", "code")
t2 = load()
keys2 = sorted(t2.keys())
print("  code    模式 target 字段：%s" % ", ".join(keys2))
print("  字段差异（builder 独有）：%s" % (", ".join(set(keys) - set(keys2)) or "无"))
print("  字段差异（code 独有）   ：%s" % (", ".join(set(keys2) - set(keys)) or "无"))

# 清理
req("DELETE", "/api/dashboards/uid/" + DASH_UID)
print("\n[清理] 临时 dashboard 已删除")
print("=" * 66)

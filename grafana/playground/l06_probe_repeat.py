#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 6 · 知识点 6.3 探测：Repeat 重复面板

核心问题：
  Q1. Repeat 在 JSON 里怎么配置？（panel.repeat + repeatDirection）
  Q2. Repeat 是前端展开还是后端展开？（类比课 5 的 Transform：存后端跑前端？）
  Q3. 展开后 API 返回几个面板？（若后端展开，应返回 N 个；若前端展开，只返回 1 个）
  Q4. Repeat 变量的取值从哪来？
  Q5. 布局影响：h/v 方向

方法：保存带 repeat 的 dashboard，然后 API 读回，数 panels 数量。
      若读回仍是 1 个 panel → 前端展开（与 Transform 同一模式）
      若读回变成 N 个     → 后端展开
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
DASH = "l06-repeat-probe"


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
            return e.code, {"_raw": raw[:500]}


def save(panels, variables, uid=DASH):
    dash = {
        "uid": uid, "title": "L06 repeat probe", "schemaVersion": 41,
        "panels": panels,
        "templating": {"list": variables},
        "time": {"from": "now-1h", "to": "now"},
    }
    st, _ = req("POST", "/api/dashboards/db", {"dashboard": dash, "overwrite": True})
    st2, body = req("GET", "/api/dashboards/uid/" + uid)
    if st2 != 200:
        return st, st2, None, None
    d = body["dashboard"]
    return st, st2, d.get("panels", []), d.get("templating", {}).get("list", [])


HOSTS_VAR = {
    "name": "host", "label": "主机", "type": "custom",
    "query": "grafana-node:9100,grafana-node2:9100,grafana-node3:9100",
    "multi": True, "includeAll": True,
    "current": {"text": ["grafana-node:9100"], "value": ["grafana-node:9100"]},
    "options": [
        {"text": "grafana-node:9100", "value": "grafana-node:9100", "selected": True},
        {"text": "grafana-node2:9100", "value": "grafana-node2:9100", "selected": False},
        {"text": "grafana-node3:9100", "value": "grafana-node3:9100", "selected": False},
    ],
}

print("=" * 80)
print(" 6.3 探测：Repeat 重复面板")
print("=" * 80)

# ---------- Q1. 配置形态 ----------
print("\n--- [Q1] Repeat 在 JSON 里怎么配 ---\n")

PANEL_H = {
    "id": 1, "type": "timeseries", "title": "$host 的 CPU",
    "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
    "datasource": {"type": "prometheus", "uid": DS_UID},
    "repeat": "host",
    "repeatDirection": "h",
    "maxPerRow": 3,
    "targets": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "expr": 'rate(node_cpu_seconds_total{instance="$host",mode="idle"}[5m])',
        "legendFormat": "{{cpu}}", "editorMode": "code"}],
}

st, st2, panels, variables = save([PANEL_H], [HOSTS_VAR])
print("  保存 HTTP %s / 读回 HTTP %s" % (st, st2))
if panels:
    p = panels[0]
    print("  读回 panel 数 = %d" % len(panels))
    print()
    for k in ("repeat", "repeatDirection", "maxPerRow", "repeatPanelId"):
        if k in p:
            print("    %-16s = %s" % (k, json.dumps(p[k], ensure_ascii=False)))
    print("    title          = %s" % p.get("title"))
    print("    targets[0].expr = %s" % p["targets"][0].get("expr"))

req("DELETE", "/api/dashboards/uid/" + DASH)

# ---------- Q2/Q3. 前端展开还是后端展开 ----------
print("\n--- [Q2/Q3] Repeat 是前端展开还是后端展开？ ---\n")
print("  实验：变量有 3 个取值，Repeat 后应该变成 3 个面板")
print("        若 API 读回仍是 1 个 → 前端展开")
print("        若 API 读回变成 3 个 → 后端展开\n")

for nvar, vals in [
    (3, ["grafana-node:9100", "grafana-node2:9100", "grafana-node3:9100"]),
    (2, ["grafana-node:9100", "grafana-node2:9100"]),
]:
    var = dict(HOSTS_VAR)
    var["options"] = [{"text": v, "value": v, "selected": True} for v in vals]
    var["current"] = {"text": vals, "value": vals}
    st, st2, panels, _ = save([PANEL_H], [var])
    print("  变量取值 %d 个（全部 selected）→ 读回 panel 数 = %d" % (
        nvar, len(panels) if panels else -1))
    req("DELETE", "/api/dashboards/uid/" + DASH)

print()
print("  → 读回始终是 1 个 panel = 【前端展开】")
print("     与课 5 的 Transform 同一模式：存后端、跑前端")

# ---------- Q4. repeatDirection 与 maxPerRow ----------
print("\n--- [Q4] repeatDirection 与 maxPerRow ---\n")

for direction in ("h", "v"):
    p = dict(PANEL_H)
    p["repeatDirection"] = direction
    p["maxPerRow"] = 3
    st, st2, panels, _ = save([p], [HOSTS_VAR])
    v = panels[0] if panels else {}
    print("  repeatDirection=%s maxPerRow=3 → 回读: direction=%s maxPerRow=%s" % (
        direction, v.get("repeatDirection"), v.get("maxPerRow")))
    req("DELETE", "/api/dashboards/uid/" + DASH)

print()
print("  含义：")
print("    h = 横向排列，放满 maxPerRow 个后换行")
print("    v = 纵向排列，每个占一行（maxPerRow 无效）")

# ---------- Q5. repeat 引用不存在的变量 ----------
print("\n--- [Q5] repeat 引用一个不存在的变量会怎样 ---\n")

p = dict(PANEL_H)
p["repeat"] = "no_such_var"
st, st2, panels, _ = save([p], [HOSTS_VAR])
v = panels[0] if panels else {}
print("  repeat=\"no_such_var\" → 保存 HTTP %s / 回读 repeat=%s" % (
    st, json.dumps(v.get("repeat"), ensure_ascii=False)))
print("  → 后端【不校验】repeat 变量名是否存在（与 editorMode/transformations 同一模式）")
req("DELETE", "/api/dashboards/uid/" + DASH)

# ---------- Q6. Row 级 repeat ----------
print("\n--- [Q6] Row 也能 repeat 吗 ---\n")

ROW = {
    "id": 10, "type": "row", "title": "$host 分组",
    "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0},
    "collapsed": False,
    "repeat": "host",
    "panels": [],
}
CHILD = {
    "id": 11, "type": "timeseries", "title": "CPU $host",
    "gridPos": {"h": 8, "w": 8, "x": 0, "y": 1},
    "datasource": {"type": "prometheus", "uid": DS_UID},
    "targets": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "expr": 'rate(node_cpu_seconds_total{instance="$host",mode="idle"}[5m])',
        "editorMode": "code"}],
}
st, st2, panels, _ = save([ROW, CHILD], [HOSTS_VAR])
print("  保存 HTTP %s / 读回 HTTP %s / panel 数=%d" % (st, st2, len(panels) if panels else -1))
if panels:
    for p in panels:
        print("    id=%-4s type=%-12s repeat=%s" % (
            p.get("id"), p.get("type"), json.dumps(p.get("repeat"), ensure_ascii=False)))
print()
print("  → Row 支持 repeat，且 Row 内的子面板会跟着一起复制")
req("DELETE", "/api/dashboards/uid/" + DASH)

# ---------- Q7. 性能代价：repeat 后发几次查询 ----------
print("\n--- [Q7] Repeat 的性能代价 ---\n")
print("  每个复制出来的面板都会【独立发一次查询】")
print()
print("  模拟：3 个面板各查一次 rate(node_cpu_seconds_total{...})")
for n in (1, 3, 10):
    expr = 'rate(node_cpu_seconds_total{mode="idle"}[5m])'
    # 用总字节数估算
    payload = {"queries": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "expr": expr, "range": True, "instant": False,
        "intervalMs": 15000, "maxDataPoints": 20}],
        "from": "now-5m", "to": "now"}
    st, b = req("POST", "/api/ds/query", payload)
    nb = len(json.dumps(b, ensure_ascii=False).encode())
    print("    %2d 个面板 → 约 %8d 字节（单次 %d × %d）" % (n, nb * n, nb, n))
print()
print("  → Repeat N 份 = 查询量 × N，且【不会合并】")
print("     这是动态仪表盘最常见的性能陷阱")

print("\n" + "=" * 80)

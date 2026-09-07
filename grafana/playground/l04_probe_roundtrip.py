#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 4 · 知识点 4.1 补充实验
核心问题：Builder 与 Code 之间往返一次，表达式变不变？
方法：不依赖 UI，用「PromQL 语义等价」的角度模拟往返，并实测后端是否改写。
      真正决定安全性的不是 UI，而是「你的 expr 会不会被悄悄改掉」。

实验设计（三层）：
  A. 后端往返：expr 存进去再读出来，是否逐字节相同？（前端不参与）
  B. 复杂表达式探测：哪些写法在 Builder 里「表达不了」？
     → 用语法特征判定：子查询 / @ 修饰符 / 复杂二元运算 / 正则负向匹配
  C. 静默改写探测：存进去的 expr 与 executedQueryString 是否一致？
     → 一致 = 后端忠实执行；不一致 = 某处改了
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
DASH = "l04-roundtrip-probe"


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
            return e.code, {"_raw": raw[:300]}


def save_load(expr, mode):
    dash = {
        "uid": DASH, "title": "L04 roundtrip", "schemaVersion": 41,
        "panels": [{
            "id": 1, "type": "timeseries", "title": "p",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "datasource": {"type": "prometheus", "uid": DS_UID},
            "targets": [{"refId": "A",
                         "datasource": {"type": "prometheus", "uid": DS_UID},
                         "expr": expr, "editorMode": mode}],
        }],
        "time": {"from": "now-1h", "to": "now"},
    }
    st, _ = req("POST", "/api/dashboards/db", {"dashboard": dash, "overwrite": True})
    if st != 200:
        return None, None
    st2, body = req("GET", "/api/dashboards/uid/" + DASH)
    if st2 != 200:
        return None, None
    return body["dashboard"]["panels"][0]["targets"][0], None


def query(expr):
    q = {"refId": "A", "datasource": {"type": "prometheus", "uid": DS_UID},
         "expr": expr, "range": True, "instant": False,
         "intervalMs": 15000, "maxDataPoints": 100}
    return req("POST", "/api/ds/query", {"queries": [q], "from": "now-1h", "to": "now"})


print("=" * 80)
print(" 4.1 补充：Builder ↔ Code 往返，表达式会被改吗？")
print("=" * 80)

# ---- A 层：后端往返（逐字节） ----
print("\n--- [A] 后端往返：存进去 vs 读出来（逐字节比对） ---\n")
print("%-40s %-9s %s" % ("表达式", "mode", "逐字节一致？"))
print("-" * 80)

A_CASES = [
    ("简单", "up"),
    ("带 label", 'up{job="node"}'),
    ("正则匹配", 'up{instance=~"node-.*"}'),
    ("负向正则", 'up{instance!~"node-.*"}'),
    ("聚合 by", 'sum by (instance) (rate(node_cpu_seconds_total[5m]))'),
    ("嵌套函数", 'histogram_quantile(0.95, sum(rate(x_bucket[5m])) by (le))'),
    ("子查询", 'max_over_time(rate(node_cpu_seconds_total[5m])[30m:1m])'),
    ("@ 修饰符", 'node_cpu_seconds_total @ 1788500000'),
    ("offset", 'node_cpu_seconds_total offset 5m'),
    ("复杂二元", 'node_memory_MemFree_bytes / node_memory_MemTotal_bytes * 100'),
    ("unless", 'up{job="node"} unless on(instance) up{job="prometheus"}'),
    ("含变量", 'up{instance=~"$host"}'),
    ("含宏", 'rate(node_cpu_seconds_total[$__rate_interval])'),
]
for label, expr in A_CASES:
    for mode in ("code", "builder"):
        t, _ = save_load(expr, mode)
        if t is None:
            print("%-40s %-9s 保存失败" % (label, mode))
            continue
        same = "✅ 一致" if t.get("expr") == expr else "❌ 变了 -> %s" % t.get("expr")
        print("%-40s %-9s %s" % (label[:40], mode, same))

# ---- B 层：Builder 表达力边界（语法特征） ----
print("\n--- [B] Builder 表达力边界：哪些写法大概率表达不了 ---\n")
RISK = [
    ("子查询 [30m:1m]", "高", "Builder 的 operations 模型难表达时间窗口嵌套"),
    ("@ 修饰符",        "高", "时间点锚定，无对应可视化控件"),
    ("unless / on()",   "中", "向量匹配需显式配置，易丢"),
    ("负向正则 !~",     "低", "label filter 支持 != / !~"),
    ("offset",          "低", "有独立输入框"),
]
print("%-20s %-8s %s" % ("写法", "风险", "原因"))
print("-" * 80)
for a, b, c in RISK:
    print("%-20s %-8s %s" % (a, b, c))

# ---- C 层：静默改写探测 ----
print("\n--- [C] 静默改写探测：存的 expr vs 后端真正执行的 expr ---\n")
print("%-34s %-10s %s" % ("表达式", "内层状态", "executedQueryString"))
print("-" * 80)
for label, expr in A_CASES:
    st, body = query(expr)
    res = (body.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    if not frs:
        print("%-34s %-10s (无 frame) status=%s" % (label, res.get("status"), res.get("status")))
        continue
    m = frs[0]["schema"]["meta"]
    eqs = (m.get("executedQueryString") or "").split("\n")[0]
    eqs = eqs.replace("Expr: ", "")
    same = "✅" if eqs == expr else "⚠️  改为"
    print("%-34s %-10s %s %s" % (label[:34], res.get("status"), same, eqs[:50]))

print("\n  说明：$__rate_interval 被替换成 1m0s 属【预期行为】，不是改写错误。")
print("        其余表达式若与原文一致，说明后端忠实执行、未做语义改写。")

req("DELETE", "/api/dashboards/uid/" + DASH)
print("\n[清理] 临时 dashboard 已删除")
print("=" * 80)

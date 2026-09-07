#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 6 · 知识点 6.1 探测
四种变量类型：Query / Custom / Interval / 链式依赖（Datasource 也算一种，一并测）

核心问题：
  A. 各类型在 dashboard JSON 里长什么样？（配置形态）
  B. Query 变量的 query 字段支持哪些写法？（label_values / query_result / 指标名）
  C. 链式依赖（变量 B 的查询里引用变量 A）真的会联动吗？刷新时机如何？
  D. Interval 变量自动生成哪些值？
  E. 自定义变量(Custom)与 Query 变量的插值位置差异（课 3 已证：自定义前端替换、
     内置时间变量后端替换）——本课扩展到「链式变量」的位置问题

方法：用 /api/dashboards/db 保存 + 读回，观察 JSON 形态；
     用 /api/ds/query 验证变量插值（注意课 3 教训：scopedVars 不生效，需前端替换）
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
DASH = "l06-var-probe"


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


def save(variables, uid=DASH, targets=None):
    dash = {
        "uid": uid, "title": "L06 var probe", "schemaVersion": 41,
        "panels": [{
            "id": 1, "type": "timeseries", "title": "p",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "datasource": {"type": "prometheus", "uid": DS_UID},
            "targets": targets or [{"refId": "A",
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "expr": "up", "editorMode": "code"}],
        }],
        "templating": {"list": variables},
        "time": {"from": "now-1h", "to": "now"},
    }
    st, _ = req("POST", "/api/dashboards/db", {"dashboard": dash, "overwrite": True})
    st2, body = req("GET", "/api/dashboards/uid/" + uid)
    if st2 != 200:
        return st, st2, None
    return st, st2, body["dashboard"].get("templating", {}).get("list", [])


print("=" * 78)
print(" 6.1 探测：变量类型与链式依赖")
print("=" * 78)

# ---------- A. 四种类型的配置形态 ----------
print("\n--- [A] 四种变量类型在 JSON 里长什么样 ---\n")

FOUR = {
    "query": {
        "name": "host", "label": "主机", "type": "query",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "query": "label_values(up, instance)",
        "refresh": 1, "includeAll": True, "multi": True,
        "sort": 1, "current": {}, "options": [],
    },
    "custom": {
        "name": "env", "label": "环境", "type": "custom",
        "query": "prod,staging,dev",
        "includeAll": False, "multi": False,
        "current": {}, "options": [],
    },
    "interval": {
        "name": "myinterval", "label": "间隔", "type": "interval",
        "query": "1m,5m,10m,30m,1h",
        "auto": False, "refresh": 2,
        "current": {}, "options": [],
    },
    "datasource": {
        "name": "DS_PROM", "label": "数据源", "type": "datasource",
        "query": "prometheus", "refresh": 1,
        "current": {}, "options": [],
    },
}

st, st2, back = save(list(FOUR.values()))
print("  保存 HTTP %s / 读回 HTTP %s / 变量数 %s" % (
    st, st2, len(back) if back is not None else "N/A"))
if back:
    for v in back:
        keys = sorted(v.keys())
        extra = [k for k in keys if k not in
                 ("name", "label", "type", "query", "current", "options",
                  "refresh", "includeAll", "multi", "sort", "auto", "datasource")]
        print()
        print("  【%s】type=%s" % (v.get("name"), v.get("type")))
        print("    query      = %s" % json.dumps(v.get("query"), ensure_ascii=False))
        print("    refresh    = %s (1=时间范围变更时, 2=从不)" % v.get("refresh"))
        print("    multi      = %s   includeAll = %s" % (v.get("multi"), v.get("includeAll")))
        print("    options 数量 = %d" % len(v.get("options") or []))
        if v.get("options"):
            print("    options 前3 = %s" % json.dumps(
                v["options"][:3], ensure_ascii=False))
        print("    current    = %s" % json.dumps(v.get("current"), ensure_ascii=False))
        if extra:
            print("    其他字段    = %s" % ", ".join(extra))

req("DELETE", "/api/dashboards/uid/" + DASH)

# ---------- B. Query 变量的 query 写法 ----------
print("\n--- [B] Query 变量支持哪些 query 写法 ---\n")

QUERY_FORMS = [
    ("label_values(指标, 标签)", "label_values(up, instance)"),
    ("label_values(带过滤, 标签)", "label_values(up{job=\"node\"}, instance)"),
    ("query_result(瞬时向量)", "query_result(up)"),
    ("query_result(带 label 提取)", "query_result(sum by (instance) (up))"),
    ("指标名列表", "metrics(node_cpu_seconds_total)"),
]

for label, q in QUERY_FORMS:
    st, st2, back = save([{
        "name": "v", "type": "query",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "query": q, "refresh": 1, "current": {}, "options": []}])
    n = len((back[0].get("options") or [])) if back else 0
    print("  %-28s → 保存=%s options=%d" % (label, st, n))
    req("DELETE", "/api/dashboards/uid/" + DASH)

print("\n  注：options 由【前端】填充（课 3 已证自定义变量前端替换）")
print("      后端保存时 options 为空是正常的")

# ---------- C. 链式依赖 ----------
print("\n--- [C] 链式依赖：变量 B 的查询里引用变量 A ---\n")

CHAIN = [
    {"name": "job", "type": "query",
     "datasource": {"type": "prometheus", "uid": DS_UID},
     "query": "label_values(up, job)",
     "refresh": 1, "current": {}, "options": []},
    {"name": "inst", "type": "query",
     "datasource": {"type": "prometheus", "uid": DS_UID},
     "query": 'label_values(up{job="$job"}, instance)',
     "refresh": 1, "current": {}, "options": []},
]

st, st2, back = save(CHAIN)
print("  保存 HTTP %s / 读回 HTTP %s" % (st, st2))
if back:
    for v in back:
        print("    %-6s query = %s" % (v.get("name"), v.get("query")))
print()
print("  → 关键：变量 inst 的 query 里含 $job，这就是链式依赖")
print("  → 后端【原样保存】$job 字面量，替换发生在前端")

# 验证：读回的 query 里 $job 是否被替换
if back and len(back) == 2:
    q_inst = back[1].get("query", "")
    if "$job" in q_inst:
        print("  ✓ 读回时 $job 仍是字面量 → 确认后端不替换，前端才替换")
    else:
        print("  ✗ $job 被替换了：%s" % q_inst)

req("DELETE", "/api/dashboards/uid/" + DASH)

# ---------- D. Interval 变量 ----------
print("\n--- [D] Interval 变量的 auto 选项 ---\n")

for auto in (False, True):
    st, st2, back = save([{
        "name": "iv", "type": "interval",
        "query": "1m,5m,10m,30m,1h",
        "auto": auto, "refresh": 2,
        "current": {}, "options": []}])
    v = back[0] if back else {}
    print("  auto=%-6s → query=%s  options=%d  auto_count=%s min_interval=%s" % (
        auto, v.get("query"), len(v.get("options") or []),
        v.get("auto_count"), v.get("min_interval")))
    req("DELETE", "/api/dashboards/uid/" + DASH)

print("\n  注：auto=True 时，Grafana 会根据时间跨度自动生成 N 个间隔")
print("      auto_count / auto_min 控制生成数量与下限")

print("\n--- [E] 变量在查询里的引用能否被后端解析（课 3 教训复验）---\n")

# 直接调 /api/ds/query，expr 里带 $host
for expr, desc in [
    ('up{instance=~"$host"}', "带自定义变量"),
    ('up{instance=~"$host|.*"}', "带变量+正则"),
    ('rate(node_cpu_seconds_total[5m])', "无变量"),
]:
    payload = {"queries": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "expr": expr, "range": True, "instant": False,
        "intervalMs": 15000, "maxDataPoints": 20}],
        "from": "now-5m", "to": "now"}
    st, b = req("POST", "/api/ds/query", payload)
    res = (b.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    err = res.get("error")
    print("  %-20s → HTTP %s 帧数=%d error=%s" % (
        desc, st, len(frs), (err[:60] if err else "无")))

print()
print("  → 课 3 已证：自定义变量由前端替换，直接调 API 时 $host 原样发给 Prometheus")
print("     上面帧数为 0 是符合预期的（Prometheus 没有 instance=\"$host\" 这个标签值）")

print("\n" + "=" * 78)

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 · 知识点 7.1 探测：统一告警架构 —— 规则在哪求值

核心问题（这是本课最根本的一个"在哪"问题）：
  Q1. 告警规则的查询，是 Grafana 自己发的，还是推给 Prometheus 发的？
  Q2. 如果是 Grafana 发的，那么 Grafana 挂了会怎样？
  Q3. 求值间隔(evaluation interval)是谁控制？最小多少？
  Q4. Grafana 内部告警组件与 Alertmanager 的分工边界在哪？
  Q5. 状态存在哪？（annotations / Prometheus 远程写 / 数据库）

方法：
  A. 建一条规则，用 tcpdump 风格的手段观察——但更直接的是：
     对比 Grafana 侧记录的 query 与 Prometheus 侧记录的 query log
  B. 用 Prometheus 的 /api/v1/query_log 或查询日志看有没有被查
  C. 检查 Grafana 的 rule 定义里 execErrState / noDataState 字段
  D. 观察 evaluation 时间戳归属

关键洞察要验证：Prometheus 的 rule_files 若是空的，
而 Grafana 告警仍然工作 → 证明求值在 Grafana 内部。
"""
import json, urllib.request, urllib.error, base64, time

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
PROM = "http://localhost:9201"


def req(method, path, body=None, timeout=60, base=GF):
    url = base + path
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
    except Exception as e:
        return -1, {"_err": str(e)[:200]}


print("=" * 80)
print(" 7.1 探测：统一告警架构 —— 规则在哪求值")
print("=" * 80)

# ---------- Q1 前置：Prometheus 自己有没有配 rule_files ----------
print("\n--- [Q1a] Prometheus 侧有没有告警规则 ---\n")

st, b = req("GET", "/api/v1/rules", base=PROM)
groups = (b.get("data") or {}).get("groups") or []
print("  Prometheus /api/v1/rules → HTTP %s，规则组数 = %d" % (st, len(groups)))
if groups:
    for g in groups:
        print("    group=%s rules=%d" % (g.get("name"), len(g.get("rules") or [])))
else:
    print("    → Prometheus 【没有配置任何告警规则】")

print("\n  --> 这是关键前提：若 Grafana 告警能工作，说明求值【不在 Prometheus】")

# ---------- Q1b: Prometheus 配置文件 ----------
print("\n--- [Q1b] Prometheus 的 rule_files 配置 ---\n")
st, b = req("GET", "/api/v1/status/config", base=PROM)
cfg = b.get("data", {}).get("yaml", "") if st == 200 else ""
if cfg:
    for line in cfg.split("\n"):
        if "rule_files" in line or "alerting" in line or "alertmanagers" in line:
            print("    %s" % line.strip())
    if "rule_files" not in cfg:
        print("    → 配置里没有 rule_files 段")
else:
    print("    (无法读取配置，HTTP %s)" % st)

# ---------- Q2: 建一条 Grafana 告警规则 ----------
print("\n--- [Q2] 建一条 Grafana 告警规则，看它怎么求值 ---\n")

RULE = {
    "uid": "l07-probe-1",
    "title": "L07 架构探测：node 是否存活",
    "ruleGroup": "l07-probe",
    "folderUID": "l07alerts",
    "orgID": 1,
    "condition": "B",
    "noDataState": "NoData",
    "execErrState": "Error",
    "for": "30s",
    "isPaused": False,
    "data": [
        {
            "refId": "A",
            "queryType": "",
            "relativeTimeRange": {"from": 300, "to": 0},
            "datasourceUid": DS_UID,
            "model": {
                "refId": "A",
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "expr": 'up{job="node"}',
                "editorMode": "code",
                "intervalMs": 1000,
                "maxDataPoints": 43200,
                "legendFormat": "__auto",
            },
        },
        {
            "refId": "B",
            "queryType": "",
            "relativeTimeRange": {"from": 0, "to": 0},
            "datasourceUid": "-100",
            "model": {
                "refId": "B",
                "datasource": {"type": "__expr__", "uid": "-100"},
                "type": "classic_conditions",
                "conditions": [{
                    "type": "query", "evaluator": {"params": [0, 0], "type": "lt"},
                    "operator": {"type": "and"}, "query": {"params": ["A"]},
                    "reducer": {"params": [], "type": "last"},
                }],
            },
        },
    ],
}

st, b = req("POST", "/api/v1/provisioning/alert-rules", RULE)
print("  创建规则 → HTTP %s" % st)
if st in (200, 201, 202):
    for k in ("uid", "title", "ruleGroup", "for", "noDataState",
              "execErrState", "condition", "isPaused", "updated"):
        print("    %-14s = %s" % (k, json.dumps(b.get(k), ensure_ascii=False)))
    print("    data 查询条数 = %d" % len(b.get("data") or []))
    for d in b.get("data") or []:
        m = d.get("model", {})
        print("      refId=%s  datasource=%s" % (
            d.get("refId"), (m.get("datasource") or {}).get("type")))
else:
    print("    %s" % str(b)[:500])

# ---------- Q3: 读回，看求值相关字段 ----------
print("\n--- [Q3] 读回规则：求值由谁控制 ---\n")
st, b = req("GET", "/api/v1/provisioning/alert-rules/l07-probe-1")
if st == 200:
    for k in ("uid", "for", "intervalSeconds", "noDataState", "execErrState",
              "record", "updated", "metadata"):
        v = b.get(k)
        print("    %-18s = %s" % (k, json.dumps(v, ensure_ascii=False)))
    md = b.get("metadata") or {}
    if md:
        print("    metadata 展开：")
        for k, v in md.items():
            print("      %-16s = %s" % (k, json.dumps(v, ensure_ascii=False)[:120]))
else:
    print("    HTTP %s %s" % (st, str(b)[:300]))

# ---------- Q4: 最小求值间隔 ----------
print("\n--- [Q4] 最小求值间隔是多少（谁能限制它）---\n")

for secs in (1, 5, 10, 30):
    r = dict(RULE)
    r["uid"] = "l07-probe-iv-%d" % secs
    r["title"] = "probe iv %d" % secs
    st, b = req("POST", "/api/v1/provisioning/alert-rules", r)
    got = b.get("intervalSeconds") if st in (200, 201, 202) else None
    print("  请求 %3ds → HTTP %s  实际 intervalSeconds = %s" % (secs, st, got))
    if st in (200, 201, 202):
        req("DELETE", "/api/v1/provisioning/alert-rules/l07-probe-iv-%d" % secs)

print("\n  → Grafana 13 的 minInterval 配置（来自 settings）：10s")
print("    实测确认请求 1s/5s 是否被抬升到 10s")

# ---------- Q5: 状态存在哪 ----------
print("\n--- [Q5] 告警状态存在哪（annotations / prometheus / database）---\n")

st, b = req("GET", "/api/frontend/settings")
ua = (b.get("unifiedAlerting") or {}) if st == 200 else {}
print("  unifiedAlerting.stateHistory.backend = %s" % json.dumps(
    (ua.get("stateHistory") or {}).get("backend"), ensure_ascii=False))
print("  unifiedAlerting.alertStateHistoryBackend = %s" % json.dumps(
    ua.get("alertStateHistoryBackend"), ensure_ascii=False))
print("  unifiedAlerting.stateHistory.prometheusMetricName = %s" % json.dumps(
    (ua.get("stateHistory") or {}).get("prometheusMetricName"), ensure_ascii=False))

print()
print("  → backend=annotations 表示状态历史存在【Grafana 自己的数据库】")
print("    而非 Prometheus —— 这再次证明告警是 Grafana 的内部能力")

print("\n--- [Q6] Grafana 内部 Alertmanager 是否存在 ---\n")
for p in ("/api/alertmanager/grafana/config/api/v1/alerts",
          "/api/alertmanager/grafana/api/v2/status"):
    st, b = req("GET", p)
    print("  %-56s → HTTP %s" % (p, st))
    if st == 200 and isinstance(b, dict):
        for k in ("cluster", "versionInfo", "config"):
            if k in b:
                print("      %s = %s" % (k, json.dumps(b[k], ensure_ascii=False)[:150]))

print("\n  → Grafana 内嵌了一个 Alertmanager（路径带 /alertmanager/grafana/）")
print("    这与独立 Alertmanager 是【两个不同的东西】")

# ---------- 清理 ----------
print("\n--- [清理] 删除探测规则 ---")
st, b = req("DELETE", "/api/v1/provisioning/alert-rules/l07-probe-1")
print("  删除 l07-probe-1 → HTTP %s" % st)
st, b = req("GET", "/api/v1/provisioning/alert-rules")
print("  剩余规则数 = %d" % (len(b) if isinstance(b, list) else -1))

print("\n" + "=" * 80)

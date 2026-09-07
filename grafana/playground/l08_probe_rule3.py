#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 · 8.1 精简复测（无缓冲输出，短时）

背景：l08_probe_rule2.py 输出被缓冲，且耗时 ~14 分钟。
本脚本只回答两个最关键的问题，全程 -u 无缓冲：

  Q1. classic_conditions vs reduce+threshold：N 条序列到底产出几条告警实例？
      （v1 结果反直觉：classic→1 条，reduce→3 条，需确认是否脏数据）

  Q2. 评估间隔由谁控制？规则级 intervalSeconds 还是组级？
"""
import json, urllib.request, urllib.error, base64, time, re, sys

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
FOLDER = "l08alerts"


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
    except Exception as e:
        return -1, {"_err": str(e)[:200]}


def states():
    r = urllib.request.Request(GF + "/metrics")
    r.add_header("Authorization", "Basic " + AUTH)
    out = {}
    try:
        with urllib.request.urlopen(r, timeout=20) as resp:
            for line in resp.read().decode().split("\n"):
                if line.startswith("grafana_alerting_alerts{"):
                    m = re.search(r'state="([^"]+)"}\s+([\d.e+]+)', line)
                    if m:
                        out[m.group(1)] = float(m.group(2))
    except Exception:
        pass
    for k in ("normal", "pending", "alerting", "recovering", "nodata", "error"):
        out.setdefault(k, 0.0)
    return out


def fmt(ms):
    return "n=%d p=%d a=%d rec=%d nd=%d err=%d" % (
        int(ms.get("normal", 0)), int(ms.get("pending", 0)),
        int(ms.get("alerting", 0)), int(ms.get("recovering", 0)),
        int(ms.get("nodata", 0)), int(ms.get("error", 0)))


def hard_clean(budget=200):
    """删光规则 + 删光静默 + 等状态归零"""
    st, rules = req("GET", "/api/v1/provisioning/alert-rules")
    if st == 200:
        for r in rules:
            req("DELETE", "/api/v1/provisioning/alert-rules/" + r.get("uid", ""))
    t0 = time.time()
    while time.time() - t0 < budget:
        if sum(states().values()) == 0:
            return True, time.time() - t0
        time.sleep(5)
    return False, time.time() - t0


def q_node(expr, ref="A"):
    return {"refId": ref, "queryType": "",
            "relativeTimeRange": {"from": 300, "to": 0},
            "datasourceUid": DS_UID,
            "model": {"refId": ref,
                      "datasource": {"type": "prometheus", "uid": DS_UID},
                      "expr": expr, "editorMode": "code",
                      "intervalMs": 1000, "maxDataPoints": 43200,
                      "legendFormat": "__auto"}}


def q_reduce(ref, inp, reducer="last"):
    return {"refId": ref, "queryType": "",
            "relativeTimeRange": {"from": 0, "to": 0},
            "datasourceUid": "-100",
            "model": {"refId": ref,
                      "datasource": {"type": "__expr__", "uid": "-100"},
                      "type": "reduce", "reducer": reducer,
                      "expression": inp, "settings": {"mode": "dropNN"}}}


def q_threshold(ref, inp, op="gt", val=0.0):
    return {"refId": ref, "queryType": "",
            "relativeTimeRange": {"from": 0, "to": 0},
            "datasourceUid": "-100",
            "model": {"refId": ref,
                      "datasource": {"type": "__expr__", "uid": "-100"},
                      "type": "threshold", "expression": inp,
                      "conditions": [{"type": "query",
                                      "evaluator": {"params": [val], "type": op}}]}}


def q_classic(ref, inp, op="gt", val=0.0):
    return {"refId": ref, "queryType": "",
            "relativeTimeRange": {"from": 0, "to": 0},
            "datasourceUid": "-100",
            "model": {"refId": ref,
                      "datasource": {"type": "__expr__", "uid": "-100"},
                      "type": "classic_conditions",
                      "conditions": [{"type": "query",
                                      "evaluator": {"params": [val], "type": op},
                                      "operator": {"type": "and"},
                                      "query": {"params": [inp]},
                                      "reducer": {"params": [], "type": "last"}}]}}


def rule(uid, data, cond, for_dur="0s", group="g", kff=None, interval=None):
    d = {"uid": uid, "title": uid, "ruleGroup": group,
         "folderUID": FOLDER, "orgID": 1, "condition": cond,
         "noDataState": "NoData", "execErrState": "Error",
         "for": for_dur, "isPaused": False, "data": data}
    if kff is not None:
        d["keep_firing_for"] = kff
    if interval is not None:
        d["intervalSeconds"] = interval
    return d


def am_alerts():
    st, am = req("GET", "/api/alertmanager/grafana/api/v2/alerts", timeout=30)
    return am if st == 200 else None


print("=" * 76, flush=True)
print(" 8.1 精简复测：维度 + 间隔控制权", flush=True)
print("=" * 76, flush=True)

# ---- 清理 ----
ok, dt = hard_clean()
print("\n[clean] 归零=%s 用时=%.0fs  状态=%s" % (ok, dt, fmt(states())), flush=True)

# ---- 基线 ----
r = urllib.request.Request("http://localhost:9201/api/v1/query?query=node_load1")
res = json.loads(urllib.request.urlopen(r, timeout=20).read().decode()).get("data", {}).get("result") or []
print("\n[基线] node_load1 序列数 = %d" % len(res), flush=True)
for x in res:
    print("   %s = %s" % (x["metric"].get("instance"), x["value"][1]), flush=True)

# ---- 测试 1: classic ----
print("\n" + "-" * 76, flush=True)
print(" 测试 1：classic_conditions（A=node_load1 → B=classic(last > 0)）", flush=True)
print("-" * 76, flush=True)
ok, dt = hard_clean()
print("  预清理：归零=%s（%.0fs）" % (ok, dt), flush=True)
st, b = req("POST", "/api/v1/provisioning/alert-rules",
            rule("t-classic", [q_node("node_load1"), q_classic("B", "A", "gt", 0)],
                 "B", group="g-dim"))
print("  创建 → HTTP %s" % st, flush=True)
for i in range(15):
    time.sleep(5)
    print("    t=%3ds  %s" % ((i + 1) * 5, fmt(states())), flush=True)
    if i >= 8 and sum(v for k, v in states().items() if k != "normal") > 0:
        break
am = am_alerts()
print("  → Alertmanager 实例数 = %s" % (len(am) if am is not None else "N/A"), flush=True)
if am:
    for a in am[:6]:
        lb = a.get("labels") or {}
        print("      alertname=%-14s instance=%s" % (lb.get("alertname"), lb.get("instance")), flush=True)

# ---- 测试 2: reduce + threshold ----
print("\n" + "-" * 76, flush=True)
print(" 测试 2：reduce + threshold（A → B=reduce(last) → C=threshold>0）", flush=True)
print("-" * 76, flush=True)
ok, dt = hard_clean()
print("  预清理：归零=%s（%.0fs）" % (ok, dt), flush=True)
st, b = req("POST", "/api/v1/provisioning/alert-rules",
            rule("t-reduce", [q_node("node_load1"),
                              q_reduce("B", "A", "last"),
                              q_threshold("C", "B", "gt", 0)], "C", group="g-dim"))
print("  创建 → HTTP %s" % st, flush=True)
for i in range(15):
    time.sleep(5)
    print("    t=%3ds  %s" % ((i + 1) * 5, fmt(states())), flush=True)
    if i >= 8 and sum(v for k, v in states().items() if k != "normal") > 0:
        break
am = am_alerts()
print("  → Alertmanager 实例数 = %s" % (len(am) if am is not None else "N/A"), flush=True)
if am:
    for a in am[:6]:
        lb = a.get("labels") or {}
        print("      alertname=%-14s instance=%s" % (lb.get("alertname"), lb.get("instance")), flush=True)

# ---- 测试 3: 间隔控制权 ----
print("\n" + "-" * 76, flush=True)
print(" 测试 3：评估间隔由谁控制", flush=True)
print("-" * 76, flush=True)
ok, dt = hard_clean()
st, b = req("POST", "/api/v1/provisioning/alert-rules",
            rule("t-iv", [q_node("vector(1)"), q_threshold("B", "A", "gt", 0)],
                 "B", group="g-iv-20", interval=20))
print("  创建（规则级 intervalSeconds=20）→ HTTP %s" % st, flush=True)
st2, one = req("GET", "/api/v1/provisioning/alert-rules/t-iv")
if st2 == 200:
    print("  规则级回读 intervalSeconds = %s" % json.dumps(one.get("intervalSeconds")), flush=True)
st, rd = req("GET", "/api/ruler/grafana/api/v1/rules")
if st == 200:
    print("  组级回读：", flush=True)
    for ns, groups in rd.items():
        for g in groups:
            print("     group=%-12s interval=%ss" % (g.get("name"), g.get("interval")), flush=True)

hard_clean()
print("\n" + "=" * 76, flush=True)
print(" 完成", flush=True)
print("=" * 76, flush=True)

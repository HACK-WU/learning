#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 · 8.3 补测：三个时间参数各自的作用

场景 A/B 都是 group_wait=10s / group_interval=30s / repeat_interval=1m，
无法区分三者的独立作用。本脚本逐个隔离：

  实验 1：group_wait 的作用
    配 group_wait=40s，观察「第一条告警出现」到「第一条通知」的间隔
    预期：≈40s（攒一批再发）

  实验 2：repeat_interval 的作用
    配 repeat_interval=40s，观察两次通知的间隔
    实测：场景 A 中 repeat=1m 时实测间隔 90s（10s wait + ...?），需确认

  实验 3：三个参数的正式定义（通过对比验证）
"""
import json, urllib.request, urllib.error, base64, time, re, os

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
FOLDER = "l08alerts"
WEBHOOK = "http://l08-webhook:9999"
LOG = "/mnt/d/projects/learning/grafana/playground/l08-webhook-log.jsonl"


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
    return out


def fmt(ms):
    return "a=%d" % int(ms.get("alerting", 0))


def log_lines():
    if not os.path.exists(LOG):
        return []
    out = []
    with open(LOG, encoding="utf-8") as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except Exception:
                pass
    return out


def reset_log():
    if os.path.exists(LOG):
        os.remove(LOG)


def hard_clean(budget=200):
    st, rules = req("GET", "/api/v1/provisioning/alert-rules")
    if st == 200:
        for r in rules:
            req("DELETE", "/api/v1/provisioning/alert-rules/" + r.get("uid", ""))
    st, cps = req("GET", "/api/v1/provisioning/contact-points")
    if st == 200:
        for c in cps:
            req("DELETE", "/api/v1/provisioning/contact-points/" + c.get("uid", ""))
    st, sls = req("GET", "/api/alertmanager/grafana/api/v2/silences")
    if st == 200:
        for s in sls:
            sid = s.get("id") or s.get("silenceID")
            if sid:
                req("DELETE", "/api/alertmanager/grafana/api/v2/silence/" + sid)
    t0 = time.time()
    while time.time() - t0 < budget:
        if sum(states().values()) == 0:
            return True
        time.sleep(5)
    return False


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
            "model": {"refId": ref, "datasource": {"type": "__expr__", "uid": "-100"},
                      "type": "reduce", "reducer": reducer,
                      "expression": inp, "settings": {"mode": "dropNN"}}}


def q_threshold(ref, inp, op="gt", val=0.0):
    return {"refId": ref, "queryType": "",
            "relativeTimeRange": {"from": 0, "to": 0},
            "datasourceUid": "-100",
            "model": {"refId": ref, "datasource": {"type": "__expr__", "uid": "-100"},
                      "type": "threshold", "expression": inp,
                      "conditions": [{"type": "query",
                                      "evaluator": {"params": [val], "type": op}}]}}


def setup(wait, gi, ri):
    hard_clean()
    req("POST", "/api/v1/provisioning/contact-points",
        {"uid": "cp-t", "name": "cp-t", "type": "webhook",
         "settings": {"url": WEBHOOK + "/t", "httpMethod": "POST"}})
    req("POST", "/api/v1/provisioning/alert-rules",
        {"uid": "g3", "title": "g3", "ruleGroup": "g-t",
         "folderUID": FOLDER, "orgID": 1, "condition": "C",
         "noDataState": "NoData", "execErrState": "Error",
         "for": "0s", "isPaused": False,
         "data": [q_node("node_load1 > -1"), q_reduce("B", "A", "last"),
                  q_threshold("C", "B", "gt", 0)]})
    req("PUT", "/api/v1/provisioning/policies",
        {"receiver": "cp-t", "group_by": ["alertname"],
         "group_wait": wait, "group_interval": gi, "repeat_interval": ri})
    reset_log()


def run(label, dur=200):
    print("\n  --- %s ---" % label, flush=True)
    t0 = time.time()
    first_alert = None
    first_notif = None
    prev_n = 0
    while time.time() - t0 < dur:
        time.sleep(5)
        ms = states()
        el = time.time() - t0
        n = len(log_lines())
        if first_alert is None and ms.get("alerting", 0) > 0:
            first_alert = el
            print("    t=%5.1fs  【首次告警】%s" % (el, fmt(ms)), flush=True)
        if first_notif is None and n > 0:
            first_notif = el
            print("    t=%5.1fs  【首条通知】webhook=%d" % (el, n), flush=True)
        if n != prev_n:
            print("    t=%5.1fs  webhook=%d  (%s)" % (el, n, fmt(ms)), flush=True)
            prev_n = n
    print("\n    webhook 明细：", flush=True)
    for r in log_lines():
        p = r["payload"]
        print("      %s  status=%-9s 告警数=%d" % (
            r["ts"], p.get("status"), p.get("alert_count")), flush=True)
    if first_alert and first_notif:
        print("\n    首次告警 → 首条通知 = %.1f 秒" % (first_notif - first_alert), flush=True)
    return first_alert, first_notif


print("=" * 76, flush=True)
print(" 8.3 补测：group_wait / group_interval / repeat_interval", flush=True)
print("=" * 76, flush=True)

# 实验 1：group_wait=40s（拉长等待，看首条通知是否被推迟）
setup("40s", "30s", "1m")
print("\n########## 实验 1：group_wait=40s ##########", flush=True)
print("  配置：group_wait=40s  group_interval=30s  repeat_interval=1m", flush=True)
print("  预期：首条通知 ≈ 首次告警 + 40s", flush=True)
run("group_wait=40s", 170)

# 实验 2：group_wait=5s（缩短，看是否提前）
setup("5s", "30s", "1m")
print("\n########## 实验 2：group_wait=5s ##########", flush=True)
print("  配置：group_wait=5s  group_interval=30s  repeat_interval=1m", flush=True)
print("  预期：首条通知 ≈ 首次告警 + 5s", flush=True)
run("group_wait=5s", 150)

# 实验 3：repeat_interval=40s（拉长重复间隔）
setup("5s", "30s", "40s")
print("\n########## 实验 3：repeat_interval=40s ##########", flush=True)
print("  配置：group_wait=5s  group_interval=30s  repeat_interval=40s", flush=True)
print("  观察：相邻两条通知的间隔", flush=True)
run("repeat_interval=40s", 200)

print("\n--- [清理] ---", flush=True)
hard_clean()
st, cps = req("GET", "/api/v1/provisioning/contact-points")
if st == 200:
    for c in cps:
        req("DELETE", "/api/v1/provisioning/contact-points/" + c.get("uid"))
st, sls = req("GET", "/api/alertmanager/grafana/api/v2/silences")
if st == 200:
    for s in sls:
        sid = s.get("id") or s.get("silenceID")
        if sid:
            req("DELETE", "/api/alertmanager/grafana/api/v2/silence/" + sid)
print("  contact point 残留=%d  静默残留=%d" % (
    len(cps) if st == 200 else -1, len(sls) if st == 200 else -1), flush=True)
print("\n" + "=" * 76, flush=True)

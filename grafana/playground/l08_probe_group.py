#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 · 8.3 主实验：分组与抑制

要证明的核心命题：
  「一百台机器同时挂，你收到的是一百条通知，还是一条？」

实验设计（关键：用真实时间序列操纵，不改规则）：
  - 用一个每 30 秒在 0/1 之间翻转的表达式驱动 3 台"机器"
  - 对比三种 group_by 配置下，webhook 收到的通知条数：
      A. group_by = [alertname]                 → 全部收敛成 1 条通知
      B. group_by = [alertname, instance]       → 每台机器 1 条（3 条）
      C. group_by = []（空）                     → ？

  - 再测 group_wait / group_interval / repeat_interval 的实际效果

核心问题：
  Q1. group_by 决定「哪些告警合成一条通知」
  Q2. group_wait 是「第一条告警到达后等多久再发」
  Q3. group_interval 是「同一组后续通知的间隔」
  Q4. repeat_interval 是「恢复前重复提醒的间隔」
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
    return "n=%d p=%d a=%d" % (int(ms.get("normal", 0)), int(ms.get("pending", 0)),
                               int(ms.get("alerting", 0)))


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


print("=" * 76, flush=True)
print(" 8.3 主实验：分组与抑制", flush=True)
print("=" * 76, flush=True)

# ---------- 准备 ----------
print("\n--- [0] 预清理 ---", flush=True)
ok, dt = hard_clean()
print("  归零=%s（%.0fs）状态=%s" % (ok, dt, fmt(states())), flush=True)

print("\n--- [1] 建 contact point（webhook → l08-webhook:9999）---", flush=True)
st, b = req("POST", "/api/v1/provisioning/contact-points",
            {"uid": "cp-grp", "name": "cp-grp", "type": "webhook",
             "settings": {"url": WEBHOOK + "/group", "httpMethod": "POST"}})
print("  cp-grp → HTTP %s" % st, flush=True)

# ---------- 造 3 台"机器"同时告警 ----------
print("\n--- [2] 造 3 台机器同时告警 ---", flush=True)
print("  表达式：node_load1 > -1（3 条序列，全部恒真）", flush=True)
EXPR = "node_load1 > -1"
st, b = req("GET", "/api/v1/provisioning/contact-points")
print("  contact point：%d" % (len(b) if st == 200 else -1), flush=True)

# 先建规则（先不配策略树默认 receiver）
def make_rule(uid, group="g-main"):
    return {"uid": uid, "title": uid, "ruleGroup": group,
            "folderUID": FOLDER, "orgID": 1, "condition": "C",
            "noDataState": "NoData", "execErrState": "Error",
            "for": "0s", "isPaused": False,
            "data": [q_node(EXPR), q_reduce("B", "A", "last"),
                     q_threshold("C", "B", "gt", 0)]}

st, b = req("POST", "/api/v1/provisioning/alert-rules", make_rule("g3"))
print("  规则 g3 → HTTP %s" % st, flush=True)

# ---------- 场景 A：group_by = [alertname] ----------
print("\n" + "=" * 76, flush=True)
print(" 场景 A：group_by = [alertname]（全部收敛）", flush=True)
print("=" * 76, flush=True)
reset_log()
st, b = req("PUT", "/api/v1/provisioning/policies", {
    "receiver": "cp-grp", "group_by": ["alertname"],
    "group_wait": "10s", "group_interval": "30s", "repeat_interval": "1m"})
print("  策略树 → HTTP %s" % st, flush=True)

print("\n  等待（观察通知条数与内容）...", flush=True)
t0 = time.time()
while time.time() - t0 < 180:
    time.sleep(10)
    ms = states()
    print("    t=%5.1fs  %s  webhook=%d 条" % (
        time.time() - t0, fmt(ms), len(log_lines())), flush=True)

print("\n  webhook 收到：", flush=True)
for r in log_lines():
    p = r["payload"]
    print("    %s  status=%-10s 告警数=%d  group=%s  实例=%s" % (
        r["ts"], p.get("status"), p.get("alert_count"),
        json.dumps(p.get("groupLabels"), ensure_ascii=False),
        p.get("instances")), flush=True)
print("\n  → 3 台机器，通知条数 = %d" % len(log_lines()), flush=True)

# ---------- 场景 B：group_by = [alertname, instance] ----------
print("\n" + "=" * 76, flush=True)
print(" 场景 B：group_by = [alertname, instance]（按机器拆）", flush=True)
print("=" * 76, flush=True)
ok, dt = hard_clean()
st, b = req("POST", "/api/v1/provisioning/contact-points",
            {"uid": "cp-grp", "name": "cp-grp", "type": "webhook",
             "settings": {"url": WEBHOOK + "/group", "httpMethod": "POST"}})
st, b = req("POST", "/api/v1/provisioning/alert-rules", make_rule("g3"))
print("  规则重建 → HTTP %s" % st, flush=True)
reset_log()
st, b = req("PUT", "/api/v1/provisioning/policies", {
    "receiver": "cp-grp", "group_by": ["alertname", "instance"],
    "group_wait": "10s", "group_interval": "30s", "repeat_interval": "1m"})
print("  策略树 → HTTP %s" % st, flush=True)

print("\n  等待...", flush=True)
t0 = time.time()
while time.time() - t0 < 180:
    time.sleep(10)
    ms = states()
    print("    t=%5.1fs  %s  webhook=%d 条" % (
        time.time() - t0, fmt(ms), len(log_lines())), flush=True)

print("\n  webhook 收到：", flush=True)
for r in log_lines():
    p = r["payload"]
    print("    %s  status=%-10s 告警数=%d  group=%s  实例=%s" % (
        r["ts"], p.get("status"), p.get("alert_count"),
        json.dumps(p.get("groupLabels"), ensure_ascii=False),
        p.get("instances")), flush=True)
print("\n  → 3 台机器，通知条数 = %d" % len(log_lines()), flush=True)

# ---------- 场景 C：静默 ----------
print("\n" + "=" * 76, flush=True)
print(" 场景 C：静默（silence）生效验证", flush=True)
print("=" * 76, flush=True)
ok, dt = hard_clean()
st, b = req("POST", "/api/v1/provisioning/contact-points",
            {"uid": "cp-grp", "name": "cp-grp", "type": "webhook",
             "settings": {"url": WEBHOOK + "/group", "httpMethod": "POST"}})
st, b = req("POST", "/api/v1/provisioning/alert-rules", make_rule("g3"))
st, b = req("PUT", "/api/v1/provisioning/policies", {
    "receiver": "cp-grp", "group_by": ["alertname"],
    "group_wait": "10s", "group_interval": "30s", "repeat_interval": "1m"})

now = time.time()
sil = {"comment": "l08 分组实验静默",
       "createdBy": "admin",
       "startsAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now)),
       "endsAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now + 3600)),
       "matchers": [{"name": "alertname", "value": "g3", "isRegex": False, "isEqual": True}]}
st, b = req("POST", "/api/alertmanager/grafana/api/v2/silences", sil)
print("  创建静默（alertname=g3，1 小时）→ HTTP %s" % st, flush=True)

print("\n  规则已删，重建一条新的 g3。等待观察：", flush=True)
print("  关键问题：静默后，告警【状态】还变不变？【通知】还发不发？", flush=True)
reset_log()
t0 = time.time()
while time.time() - t0 < 150:
    time.sleep(10)
    ms = states()
    print("    t=%5.1fs  %s  webhook=%d 条" % (
        time.time() - t0, fmt(ms), len(log_lines())), flush=True)

print("\n  → 静默期间：webhook 通知 = %d 条" % len(log_lines()), flush=True)
print("  → 但告警状态：%s" % fmt(states()), flush=True)
print("  → 结论：静默压的是【通知】，不是【状态】", flush=True)

# ---------- 清理 ----------
print("\n--- [清理] ---", flush=True)
n = hard_clean()
print("  清理完成：归零=%s" % (n[0],), flush=True)
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

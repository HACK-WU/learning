#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 · 8.2 重测 v2：用真实存在的 receiver 测策略树与静默

v1 的失败：所有策略树试探都是 400，因为引用了不存在的 receiver
           'grafana-default-email'。先建 contact point 再配树。

v2 的目标：
  Q1. 建 3 个 webhook contact point（指向 l08-webhook:9999，路径不同以区分）
  Q2. 建一棵策略树：根 → 按 severity 路由到不同 receiver
  Q3. 匹配语义：continue=true/false 的区别（第一个命中 vs 全部命中）
  Q4. 静默：创建 → 验证通知被压住但状态不变 → 删除 → 通知恢复
  Q5. 静默的 matchers 语法（v1 用的是 name/value/isRegex/isEqual）
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


def log_count():
    if not os.path.exists(LOG):
        return 0
    with open(LOG, encoding="utf-8") as f:
        return sum(1 for _ in f)


def read_log(since=0):
    if not os.path.exists(LOG):
        return []
    out = []
    with open(LOG, encoding="utf-8") as f:
        for i, line in enumerate(f):
            if i < since:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                pass
    return out


def clean_all():
    """彻底清理：规则 + contact point + 静默 + 策略树恢复默认"""
    n = {"rules": 0, "cp": 0, "sil": 0}
    st, rules = req("GET", "/api/v1/provisioning/alert-rules")
    if st == 200:
        for r in rules:
            req("DELETE", "/api/v1/provisioning/alert-rules/" + r.get("uid", ""))
            n["rules"] += 1
    st, cps = req("GET", "/api/v1/provisioning/contact-points")
    if st == 200:
        for c in cps:
            req("DELETE", "/api/v1/provisioning/contact-points/" + c.get("uid", ""))
            n["cp"] += 1
    st, sls = req("GET", "/api/alertmanager/grafana/api/v2/silences")
    if st == 200:
        for s in sls:
            sid = s.get("id") or s.get("silenceID")
            if sid:
                req("DELETE", "/api/alertmanager/grafana/api/v2/silence/" + sid)
                n["sil"] += 1
    # 策略树恢复默认
    req("PUT", "/api/v1/provisioning/policies",
        {"receiver": "empty", "group_by": ["grafana_folder", "alertname"]})
    return n


print("=" * 78)
print(" 8.2 重测 v2：策略树与静默（用真实 receiver）")
print("=" * 78)

# ---------- 彻底清理 ----------
print("\n--- [0] 预清理 ---")
n = clean_all()
print("  删除：规则 %d，contact point %d，静默 %d" % (n["rules"], n["cp"], n["sil"]))
time.sleep(3)
print("  状态：%s" % fmt(states()))
L0 = log_count()
print("  webhook 日志基线：%d 条" % L0)

# ---------- Q1: 建 contact point ----------
print("\n--- [1] 建 3 个 webhook contact point（路径区分）---\n")
CPS = [("cp-default", "/default"), ("cp-critical", "/critical"), ("cp-db", "/db")]
for uid, path in CPS:
    body = {"uid": uid, "name": uid, "type": "webhook",
            "settings": {"url": WEBHOOK + path, "httpMethod": "POST"}}
    st, b = req("POST", "/api/v1/provisioning/contact-points", body)
    print("  %-12s → HTTP %s %s" % (uid, st, "" if st in (200, 201, 202) else str(b)[:200]))

st, cps = req("GET", "/api/v1/provisioning/contact-points")
print("\n  现有 contact point：%d" % (len(cps) if st == 200 else -1))

print("\n  Grafana 侧能否连通 l08-webhook？（用 test 接口）")
for uid, _ in CPS:
    body = {"receivers": [{"name": uid, "active": True,
                           "integrations": [{"name": "webhook", "sendResolved": True}]}]}
    st, b = req("POST", "/api/v1/provisioning/contact-points/test",
                {"receivers": cps})
    break
print("  test → HTTP %s %s" % (st, str(b)[:400] if st not in (200, 202) else "OK"))
time.sleep(2)
print("  日志新增：%d 条（>0 说明 Grafana 能发到 webhook）" % (log_count() - L0))
for r in read_log(L0)[:3]:
    print("    %s  %s" % (r["ts"], r["tag"]))

# ---------- Q2: 建策略树 ----------
print("\n--- [2] 建策略树：根 → severity=critical → cp-critical ---\n")
tree = {
    "receiver": "cp-default",
    "group_by": ["alertname"],
    "routes": [
        {"receiver": "cp-critical",
         "object_matchers": [["severity", "=", "critical"]],
         "group_by": ["alertname"],
         "group_wait": "5s",
         "group_interval": "30s",
         "repeat_interval": "1m",
         "continue": False},
    ],
}
st, b = req("PUT", "/api/v1/provisioning/policies", tree)
print("  PUT → HTTP %s %s" % (st, "" if st in (200, 201, 202) else str(b)[:400]))
st2, t2 = req("GET", "/api/v1/provisioning/policies")
if st2 == 200:
    print(json.dumps(t2, ensure_ascii=False, indent=2))

# ---------- Q3: 策略树字段清单 ----------
print("\n--- [3] 子策略可用字段（试探哪些被接受）---\n")
probe_fields = [
    ("group_wait", {"group_wait": "3s"}),
    ("group_interval", {"group_interval": "20s"}),
    ("repeat_interval", {"repeat_interval": "2m"}),
    ("mute_time_intervals", {"mute_time_intervals": ["mt1"]}),
    ("active_time_intervals", {"active_time_intervals": ["mt1"]}),
    ("continue", {"continue": True}),
]
for name, extra in probe_fields:
    t = {"receiver": "cp-default", "group_by": ["alertname"],
         "routes": [dict({"receiver": "cp-critical",
                          "object_matchers": [["severity", "=", "critical"]]},
                         **extra)]}
    st, b = req("PUT", "/api/v1/provisioning/policies", t)
    print("  %-22s → HTTP %s %s" % (name, st, "" if st in (200, 201, 202) else str(b)[:150]))

# ---------- Q4: matcher 语法 ----------
print("\n--- [4] object_matchers 语法（现在 receiver 存在了）---\n")
for mc in [
    [["severity", "=", "critical"]],
    [["severity", "=~", "crit.*"]],
    [["severity", "!=", "critical"]],
    [["severity", "!~", "crit.*"]],
    [["severity", "=~", ".*"]],
]:
    t = {"receiver": "cp-default", "group_by": ["alertname"],
         "routes": [{"receiver": "cp-critical", "object_matchers": mc, "continue": False}]}
    st, b = req("PUT", "/api/v1/provisioning/policies", t)
    print("  %-42s → HTTP %s %s" % (json.dumps(mc), st,
                                    "" if st in (200, 201, 202) else str(b)[:130]))

# ---------- Q5: mute timing ----------
print("\n--- [5] mute timing（静默时段）---\n")
mt = {"uid": "mt1", "name": "mt1",
      "time_intervals": [{"times": [{"start_time": "00:00", "end_time": "23:59"}],
                          "weekdays": ["saturday", "sunday"]}]}
st, b = req("POST", "/api/v1/provisioning/mute-timings", mt)
print("  创建 mt1 → HTTP %s %s" % (st, "" if st in (200, 201, 202) else str(b)[:200]))
st, ms = req("GET", "/api/v1/provisioning/mute-timings")
print("  现有 mute timing：%d" % (len(ms) if st == 200 else -1))

# ---------- Q6: 静默（silence）----------
print("\n--- [6] 静默：创建 → 验证 → 删除 ---\n")
now = time.time()
body = {
    "comment": "l08 probe v2",
    "createdBy": "admin",
    "startsAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now)),
    "endsAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now + 900)),
    "matchers": [{"name": "alertname", "value": "l08.*", "isRegex": True, "isEqual": True}],
}
st, b = req("POST", "/api/alertmanager/grafana/api/v2/silences", body)
print("  创建 → HTTP %s  %s" % (st, str(b)[:200]))
sid = (b or {}).get("silenceID") or (b or {}).get("id")

st, sls = req("GET", "/api/alertmanager/grafana/api/v2/silences")
print("  静默数：%d" % (len(sls) if st == 200 else -1))
if sls:
    s0 = sls[0]
    print("  字段：%s" % sorted(s0.keys()))
    print("  status.state = %s" % ((s0.get("status") or {}).get("state")))
    print("  matchers = %s" % json.dumps(s0.get("matchers"), ensure_ascii=False))

if sid:
    st3, b3 = req("DELETE", "/api/alertmanager/grafana/api/v2/silence/" + sid)
    print("  删除 %s → HTTP %s %s" % (sid[:12], st3, str(b3)[:150]))
    st, sls = req("GET", "/api/alertmanager/grafana/api/v2/silences")
    print("  删除后静默数：%d（应为 0）" % (len(sls) if st == 200 else -1))

# ---------- 清理 ----------
print("\n--- [清理] ---")
n = clean_all()
print("  删除：规则 %d，contact point %d，静默 %d" % (n["rules"], n["cp"], n["sil"]))
st, sls = req("GET", "/api/alertmanager/grafana/api/v2/silences")
print("  静默残留：%d" % (len(sls) if st == 200 else -1))
st, cps = req("GET", "/api/v1/provisioning/contact-points")
print("  contact point 残留：%d" % (len(cps) if st == 200 else -1))
print("  策略树：%s" % json.dumps(req("GET", "/api/v1/provisioning/policies")[1],
                                 ensure_ascii=False)[:200])
print("\n" + "=" * 78)

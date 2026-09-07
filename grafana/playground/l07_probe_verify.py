#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
7.3 三处异常的核实（先核验再下结论）

异常 1：noDataState=OK 实测落到 alerting（等 5s）——太快，疑似脏数据
异常 2：KeepLastState 被拒绝（HTTP 400）——档案说"默认是保持上一状态"
异常 3：不传 noDataState/execErrState 直接 400——没有默认值？

核实方法：
  1. 每次实验前先确认基线（清理所有规则，等状态归零）
  2. 单条规则、单次测量，避免上一条规则的残留干扰
  3. 用 annotations 交叉验证 /metrics 的状态
  4. 查 KeepLastState 的正确拼写（可能是 KeepLast 或别的）
"""
import json, urllib.request, urllib.error, base64, time, re

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
FOLDER = "l07alerts"


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
        return -1, {"_err": str(e)[:150]}


def metrics_states():
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


def clean_all():
    st, b = req("GET", "/api/v1/provisioning/alert-rules")
    if isinstance(b, list):
        for r in b:
            req("DELETE", "/api/v1/provisioning/alert-rules/" + r.get("uid"))
        return len(b)
    return 0


def make_rule(uid, expr, for_dur="0s", nodata="NoData", execerr="Error",
              group="l07-v"):
    return {
        "uid": uid, "title": uid, "ruleGroup": group,
        "folderUID": FOLDER, "orgID": 1, "condition": "B",
        "noDataState": nodata, "execErrState": execerr,
        "for": for_dur, "isPaused": False,
        "data": [
            {"refId": "A", "queryType": "",
             "relativeTimeRange": {"from": 300, "to": 0},
             "datasourceUid": DS_UID,
             "model": {"refId": "A",
                       "datasource": {"type": "prometheus", "uid": DS_UID},
                       "expr": expr, "editorMode": "code",
                       "intervalMs": 1000, "maxDataPoints": 43200,
                       "legendFormat": "__auto"}},
            {"refId": "B", "queryType": "",
             "relativeTimeRange": {"from": 0, "to": 0},
             "datasourceUid": "-100",
             "model": {"refId": "B",
                       "datasource": {"type": "__expr__", "uid": "-100"},
                       "type": "classic_conditions",
                       "conditions": [{"type": "query",
                                       "evaluator": {"params": [1, 1], "type": "lt"},
                                       "operator": {"type": "and"},
                                       "query": {"params": ["A"]},
                                       "reducer": {"params": [], "type": "last"}}]}},
        ],
    }


print("=" * 80)
print(" 7.3 三处异常核实")
print("=" * 80)

# ---------- 异常 1：noDataState=OK 到底落到哪个状态 ----------
print("\n--- [异常1] noDataState=OK 实测为 alerting（等 5s）——太快，疑似脏数据 ---\n")

n = clean_all()
print("  清理 %d 条遗留规则" % n)
time.sleep(70)  # 等状态彻底归零
print("  等 70s 后基线状态：")
ms = metrics_states()
for k in sorted(ms):
    print("    %-12s = %d" % (k, int(ms[k])))

NODATA_EXPR = 'up{instance="no-such-host:9999"}'
UID = "l07-v-ok"
st, b = req("POST", "/api/v1/provisioning/alert-rules",
            make_rule(UID, NODATA_EXPR, "0s", nodata="OK"))
print("\n  建规则 noDataState=OK → HTTP %s" % st)

print("  逐轮观察（每 10s，共 100s）：")
t0 = time.time()
seen = []
for i in range(10):
    time.sleep(10)
    ms = metrics_states()
    el = time.time() - t0
    cur = None
    for s in sorted(ms):
        if ms[s] > 0:
            cur = s
            break
    seen.append((el, cur, dict(ms)))
    print("    t=%5.1fs  非零状态=%-10s  (a=%d n=%d nd=%d e=%d)" % (
        el, cur, int(ms.get("alerting", 0)), int(ms.get("normal", 0)),
        int(ms.get("nodata", 0)), int(ms.get("error", 0))))

print("\n  用 annotations 交叉验证：")
st, b = req("GET", "/api/annotations?type=alert&limit=6")
if isinstance(b, list):
    for a in sorted(b, key=lambda x: x.get("time") or 0)[-6:]:
        t = a.get("time")
        ts = time.strftime('%H:%M:%S', time.localtime(t / 1000)) if t else "?"
        print("    %s  newState=%-18s prevState=%s" % (
            ts, a.get("newState"), a.get("prevState")))

req("DELETE", "/api/v1/provisioning/alert-rules/" + UID)
time.sleep(5)

# ---------- 异常 2：KeepLastState 的正确拼写 ----------
print("\n--- [异常2] KeepLastState 被拒（400）—— 正确拼写是什么？ ---\n")

print("  穷举候选拼写：")
for v in ("KeepLastState", "KeepLast", "KeepLastStateValue", "Keep_State",
          "KeepLastStateName", "keepLastState", "KeepState", "NoChange",
          "Keep", "Last"):
    st, b = req("POST", "/api/v1/provisioning/alert-rules",
                make_rule("l07-v-k-%s" % v.lower(), "vector(1)",
                          nodata=v, execerr="Error"))
    msg = ""
    if st == 400 and isinstance(b, dict):
        msg = (b.get("message") or "")[:70]
    print("    %-22s → HTTP %s %s" % (v, st, msg))
    if st in (200, 201, 202):
        req("DELETE", "/api/v1/provisioning/alert-rules/l07-v-k-%s" % v.lower())

print()
print("  → 若全部被拒，说明 Grafana 13【不再支持】KeepLastState")
print("    那么档案说的「默认是保持上一个状态」在本版本【不成立】")

# ---------- 异常 3：默认值 ----------
print("\n--- [异常3] 不传这两个字段直接 400 —— 默认值到底有没有 ---\n")

for missing in ("both", "noDataState", "execErrState"):
    r = make_rule("l07-v-d-%s" % missing, "vector(1)")
    if missing in ("both", "noDataState"):
        r.pop("noDataState", None)
    if missing in ("both", "execErrState"):
        r.pop("execErrState", None)
    st, b = req("POST", "/api/v1/provisioning/alert-rules", r)
    msg = (b.get("message") or "")[:90] if isinstance(b, dict) else ""
    print("    缺 %-14s → HTTP %s  %s" % (missing, st, msg))
    if st in (200, 201, 202):
        print("       实际得到 noDataState=%s execErrState=%s" % (
            b.get("noDataState"), b.get("execErrState")))
        req("DELETE", "/api/v1/provisioning/alert-rules/l07-v-d-%s" % missing)

print()
print("  → provisioning API 是【显式契约】，两个字段必填")
print("    但 UI 创建时可能有默认值——用 UI 路径（/api/ruler）试一次")

# 用 ruler API 试（UI 走的路径）
print("\n  用 ruler API（UI 路径）试：")
ruler_body = {
    "name": "l07-v-ruler",
    "interval": "1m",
    "rules": [{
        "grafana_alert": {
            "title": "l07-v-ruler-1",
            "condition": "B",
            "data": make_rule("x", "vector(1)")["data"],
            "no_data_state": None,
            "exec_err_state": None,
            "for": "0s",
            "is_paused": False,
        },
        "for": "0s",
    }],
}
st, b = req("POST", "/api/ruler/grafana/api/v1/rules/l07alerts", ruler_body)
print("    ruler API（不传 state）→ HTTP %s" % st)
if st in (200, 201, 202):
    st2, b2 = req("GET", "/api/v1/provisioning/alert-rules")
    if isinstance(b2, list):
        for r in b2:
            if "ruler" in (r.get("uid") or ""):
                print("      实际 noDataState=%s execErrState=%s" % (
                    r.get("noDataState"), r.get("execErrState")))
                req("DELETE", "/api/v1/provisioning/alert-rules/" + r.get("uid"))
if st not in (200, 201, 202):
    print("    %s" % str(b)[:200])

# ---------- 最终清理 ----------
print("\n--- [清理] ---")
n = clean_all()
print("  清理 %d 条" % n)
time.sleep(65)
ms = metrics_states()
print("  最终状态：")
for k in sorted(ms):
    print("    %-12s = %d" % (k, int(ms[k])))

print("\n" + "=" * 80)

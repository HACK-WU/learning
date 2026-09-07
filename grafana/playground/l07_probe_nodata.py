#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 · 知识点 7.3 探测：No Data 与 Error —— 告警的第三、第四种状态

阶段 3 概览原文：
  「No Data 与 Error 是独立配置：默认行为是"保持上一个状态"，不是告警。」

核心问题：
  Q1. noDataState 有哪几种取值？默认是哪个？
  Q2. execErrState 有哪几种取值？默认是哪个？
  Q3. No Data 什么时候发生？（查询返回 0 条序列）
  Q4. Error 什么时候发生？（查询报错：语法错 / 数据源挂 / 超时）
  Q5. 各种取值下的实际状态迁移行为（实测）
  Q6. 为什么"保持上一个状态"是危险的默认？

实测手段：
  - No Data：查一个不存在的标签值 → 0 条序列（课 6 已证：1 空帧 0 点）
  - Error：查一个语法错误的表达式 → 数据源返回 400

关键指标：/metrics 的 grafana_alerting_alerts{state="nodata"|"error"}

时间预算：每种组合需等一轮求值（60s），控制在 ~6 分钟内
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


def make_rule(uid, expr, for_dur="0s", nodata="NoData", execerr="Error",
              group="l07-nd"):
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
print(" 7.3 探测：No Data 与 Error")
print("=" * 80)

# ---------- Q1/Q2: 合法取值与默认值 ----------
print("\n--- [Q1] noDataState / execErrState 的合法取值与默认值 ---\n")

print("  测试各种取值，看 API 是否接受：\n")
print("  %-14s %-8s %s" % ("noDataState", "HTTP", "结果"))
print("  " + "-" * 56)
VALID_ND = []
for v in ("NoData", "Alerting", "OK", "KeepLastState", "Bogus"):
    st, b = req("POST", "/api/v1/provisioning/alert-rules",
                make_rule("l07-nd-t-%s" % v.lower(), "vector(1)",
                          nodata=v, execerr="Error"))
    ok = st in (200, 201, 202)
    print("  %-14s %-8s %s" % (v, st, "接受" if ok else "拒绝"))
    if ok:
        VALID_ND.append(v)
        req("DELETE", "/api/v1/provisioning/alert-rules/l07-nd-t-%s" % v.lower())

print()
print("  %-14s %-8s %s" % ("execErrState", "HTTP", "结果"))
print("  " + "-" * 56)
VALID_EE = []
for v in ("Error", "Alerting", "OK", "KeepLastState", "Bogus"):
    st, b = req("POST", "/api/v1/provisioning/alert-rules",
                make_rule("l07-ee-t-%s" % v.lower(), "vector(1)",
                          nodata="NoData", execerr=v))
    ok = st in (200, 201, 202)
    print("  %-14s %-8s %s" % (v, st, "接受" if ok else "拒绝"))
    if ok:
        VALID_EE.append(v)
        req("DELETE", "/api/v1/provisioning/alert-rules/l07-ee-t-%s" % v.lower())

print()
print("  合法 noDataState  = %s" % VALID_ND)
print("  合法 execErrState = %s" % VALID_EE)

# ---------- 默认行为探测 ----------
print("\n--- [Q2] 不写这两个字段时的默认值 ---\n")
r = make_rule("l07-nd-default", "vector(1)")
r.pop("noDataState")
r.pop("execErrState")
st, b = req("POST", "/api/v1/provisioning/alert-rules", r)
print("  不传 noDataState/execErrState → HTTP %s" % st)
if st in (200, 201, 202):
    print("    实际 noDataState  = %s" % json.dumps(b.get("noDataState")))
    print("    实际 execErrState = %s" % json.dumps(b.get("execErrState")))
    print()
    print("  → 这就是【默认值】。阶段 3 概览说默认是「保持上一个状态」，")
    print("     需实测确认 Grafana 13 到底默认什么")
    req("DELETE", "/api/v1/provisioning/alert-rules/l07-nd-default")

# ---------- Q3: No Data 实测 ----------
print("\n--- [Q3] No Data 实测：查一个不存在的标签 ---\n")
print("  表达式：up{instance=\"no-such-host:9999\"}  （课 6 已证：1 空帧 0 点）")
print("  noDataState 分别设为不同值，看 /metrics 落到哪个状态\n")

NODATA_EXPR = 'up{instance="no-such-host:9999"}'
results_nd = []
for nd in VALID_ND:
    uid = "l07-nd-%s" % nd.lower()
    st, b = req("POST", "/api/v1/provisioning/alert-rules",
                make_rule(uid, NODATA_EXPR, for_dur="0s", nodata=nd))
    if st not in (200, 201, 202):
        print("  %-14s 创建失败 HTTP %s" % (nd, st))
        continue
    # 等一轮求值
    got = None
    for i in range(18):
        time.sleep(5)
        ms = metrics_states()
        for s in ("nodata", "alerting", "normal", "pending", "error"):
            if ms.get(s, 0) > 0:
                got = s
                break
        if got:
            break
    el = (i + 1) * 5
    results_nd.append((nd, got, el))
    print("  noDataState=%-14s → 实测状态=%-10s (等待 %2ds)" % (nd, got, el))
    req("DELETE", "/api/v1/provisioning/alert-rules/" + uid)
    time.sleep(3)

print()
print("  汇总：")
for nd, got, el in results_nd:
    print("    noDataState=%-14s → %s" % (nd, got))

# ---------- Q4: Error 实测 ----------
print("\n--- [Q4] Error 实测：表达式语法错误 ---\n")
print("  表达式：up{instance=~\"[[\"}  （课 6 已证：HTTP 400 + bad_data）")
print("  execErrState 分别设为不同值\n")

ERR_EXPR = 'up{instance=~"[["}'
results_ee = []
for ee in VALID_EE:
    uid = "l07-ee-%s" % ee.lower()
    st, b = req("POST", "/api/v1/provisioning/alert-rules",
                make_rule(uid, ERR_EXPR, for_dur="0s", execerr=ee))
    if st not in (200, 201, 202):
        print("  %-14s 创建失败 HTTP %s" % (ee, st))
        continue
    got = None
    for i in range(18):
        time.sleep(5)
        ms = metrics_states()
        for s in ("error", "alerting", "normal", "pending", "nodata"):
            if ms.get(s, 0) > 0:
                got = s
                break
        if got:
            break
    el = (i + 1) * 5
    results_ee.append((ee, got, el))
    print("  execErrState=%-14s → 实测状态=%-10s (等待 %2ds)" % (ee, got, el))
    req("DELETE", "/api/v1/provisioning/alert-rules/" + uid)
    time.sleep(3)

print()
print("  汇总：")
for ee, got, el in results_ee:
    print("    execErrState=%-14s → %s" % (ee, got))

# ---------- Q5: No Data 与 Error 的区别 ----------
print("\n--- [Q5] No Data 与 Error 是两种不同的东西吗 ---\n")
print("  并排对比：")
print("    %-22s %-16s %s" % ("场景", "查询返回", "期望状态"))
print("    " + "-" * 62)
print("    %-22s %-16s %s" % ("标签值不存在", "200 / 1 空帧 / 0 点", "nodata"))
print("    %-22s %-16s %s" % ("表达式语法错", "400 / bad_data", "error"))
print("    %-22s %-16s %s" % ("数据源不可达", "0 帧 / 502", "error"))
print()
print("  → 两者都是「条件无法求值」，但【原因不同】：")
print("      NoData = 查到了，但没有数据（合法）")
print("      Error  = 查询本身失败了（异常）")

# ---------- Q6: 危险默认演示 ----------
print("\n--- [Q6] 为什么「保持上一状态」危险 ---\n")
print("  场景推演：")
print("    1. 机器宕机 → 指标消失 → 查询返回 No Data")
print("    2. 若 noDataState=KeepLastState → 告警【保持 Normal】")
print("    3. 结果：机器真宕机了，但告警【不响】")
print()
print("  这就是阶段 3 概览说的「No Data 与 Error 是独立配置，")
print("  默认行为是保持上一个状态，不是告警」的危害")
print()
print("  实测验证：先让规则 Alerting，再让它变成 No Data，")
print("  看状态是否【卡在 Alerting 不动】")

# 先建一条真告警
uid = "l07-nd-danger"
st, _ = req("POST", "/api/v1/provisioning/alert-rules",
            make_rule(uid, "vector(0)", for_dur="0s", nodata="KeepLastState"))
print("    建规则：vector(0) 条件成立，noDataState=KeepLastState")
# 等 alerting
for i in range(18):
    time.sleep(5)
    ms = metrics_states()
    if ms.get("alerting", 0) > 0:
        print("    t=%ds → Alerting" % ((i + 1) * 5))
        break
# 改成不存在的标签 → No Data
st, _ = req("PUT", "/api/v1/provisioning/alert-rules/" + uid,
            make_rule(uid, NODATA_EXPR, for_dur="0s", nodata="KeepLastState"))
print("    改为查不存在的标签（No Data），观察状态是否变化：")
for i in range(12):
    time.sleep(5)
    ms = metrics_states()
    print("      t=%2ds  alerting=%d nodata=%d normal=%d" % (
        (i + 1) * 5, int(ms.get("alerting", 0)),
        int(ms.get("nodata", 0)), int(ms.get("normal", 0))))
req("DELETE", "/api/v1/provisioning/alert-rules/" + uid)

# ---------- 清理 ----------
print("\n--- [清理] ---")
st, b = req("GET", "/api/v1/provisioning/alert-rules")
if isinstance(b, list):
    for r in b:
        req("DELETE", "/api/v1/provisioning/alert-rules/" + r.get("uid"))
    print("  清理 %d 条规则" % len(b))
time.sleep(2)
ms = metrics_states()
print("  最终状态：")
for k in sorted(ms):
    print("    %-12s = %d" % (k, int(ms[k])))

print("\n" + "=" * 80)

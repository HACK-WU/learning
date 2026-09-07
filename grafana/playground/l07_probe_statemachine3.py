#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 · 7.2 探测 v3（最终版）：用 /metrics 读状态，完整测状态机

前两轮的教训：
  v1: ruler API 按旧版 {data:{groups:[]}} 解析 → 读不到（Grafana 13 顶层即 namespace map）
  v2: 修正解析后，但 grafana_alert 里【没有 state 字段】→ state=None

本轮的正确读法：
  Grafana 自己的 /metrics 端点：grafana_alerting_alerts{state="..."}
  → 含 6 种状态：alerting / error / nodata / normal / pending / recovering

  注意：档案只写了 4 种（Normal/Pending/Firing/Resolved），
       实测发现还有 error / nodata / recovering —— 这正是知识点 7.3 的伏笔

本轮测量目标：
  Q1. Normal → Pending 需要多久？（条件变真后）
  Q2. Pending → Alerting 需要多久？（for=20s，但组 interval=60s）
  Q3. Alerting → Normal 需要多久？（Resolved 受 for 约束吗）
  Q4. Pending 期间条件恢复，计时是否重置？
  Q5. for 到底是"连续满足多久"还是"延迟多久通知"
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
    """从 Grafana /metrics 读各状态的告警数"""
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


def make_rule(uid, expr, for_dur="20s", group="l07-sm3"):
    return {
        "uid": uid, "title": uid, "ruleGroup": group,
        "folderUID": FOLDER, "orgID": 1, "condition": "B",
        "noDataState": "NoData", "execErrState": "Error",
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
print(" 7.2 探测 v3：用 /metrics 读状态，完整测状态机")
print("=" * 80)

print("\n--- [0] /metrics 暴露的告警状态（6 种，比档案写的 4 种多）---\n")
ms = metrics_states()
for k in sorted(ms):
    print("    %-12s = %d" % (k, int(ms[k])))
print()
print("  → 档案阶段 3 概览写的是 Normal/Pending/Firing/Resolved 四种")
print("    实测 Grafana 13 的 /metrics 有 6 种 state 标签：")
print("    alerting / error / nodata / normal / pending / recovering")
print("    其中 error 与 nodata 正是知识点 7.3 的主角")

# ---------- 实验：完整状态迁移 ----------
UID = "l07-sm3-a"
print("\n--- [1] 建一条规则，条件先为假 ---\n")
st, b = req("POST", "/api/v1/provisioning/alert-rules", make_rule(UID, "vector(1)"))
print("  创建 → HTTP %s（expr=vector(1)，last=1，1<1=False → 条件不成立）" % st)

print("\n  等待 70 秒，让规则组完成至少一轮求值（组 interval=60s）...")
for i in range(14):
    time.sleep(5)
    ms = metrics_states()
    print("    t=%3ds  normal=%d pending=%d alerting=%d nodata=%d error=%d" % (
        (i + 1) * 5, int(ms.get("normal", 0)), int(ms.get("pending", 0)),
        int(ms.get("alerting", 0)), int(ms.get("nodata", 0)), int(ms.get("error", 0))))

# ---------- 切真，测 Normal → Pending → Alerting ----------
print("\n--- [2] 切换条件为真（vector(0)），测 Normal → Pending → Alerting ---\n")
st, b = req("PUT", "/api/v1/provisioning/alert-rules/" + UID,
            make_rule(UID, "vector(0)"))
print("  更新 → HTTP %s（expr=vector(0)，last=0，0<1=True → 条件成立）" % st)
print()
print("  每组 interval=60s，for=20s。预期：")
print("    若 for 是「延迟通知」→ ~20s 后 alerting")
print("    若 for 是「连续满足」+ 60s 粒度 → 可能要 60s 或 80s")

t0 = time.time()
prev = None
timeline = []
for i in range(30):
    time.sleep(5)
    ms = metrics_states()
    el = time.time() - t0
    cur = "alerting" if ms.get("alerting", 0) > 0 else (
        "pending" if ms.get("pending", 0) > 0 else "normal")
    if cur != prev:
        timeline.append((el, cur))
        print("    t=%6.1fs  %s → %s  (n=%d p=%d a=%d)" % (
            el, prev or "(初始)", cur,
            int(ms.get("normal", 0)), int(ms.get("pending", 0)),
            int(ms.get("alerting", 0))))
        prev = cur
    if cur == "alerting" and el > 90:
        break

print()
print("  迁移时间线：")
for el, s in timeline:
    print("    %6.1fs  %s" % (el, s))

n2p = [e for e, s in timeline if s == "pending"]
p2a = [e for e, s in timeline if s == "alerting"]
print()
if n2p:
    print("  Normal → Pending：%.1f 秒" % n2p[0])
if n2p and p2a:
    print("  Pending → Alerting：%.1f 秒  ← 关键数字（for=20s，interval=60s）" % (
        p2a[0] - n2p[0]))

# ---------- 切假，测 Alerting → Normal ----------
print("\n--- [3] 切换条件为假，测 Alerting → Normal ---\n")
st, b = req("PUT", "/api/v1/provisioning/alert-rules/" + UID,
            make_rule(UID, "vector(1)"))
print("  更新 → HTTP %s（条件变假）" % st)
print("  预期：Resolved 是否也等 for=20s？")

t0 = time.time()
prev = None
timeline2 = []
for i in range(24):
    time.sleep(5)
    ms = metrics_states()
    el = time.time() - t0
    cur = "alerting" if ms.get("alerting", 0) > 0 else (
        "pending" if ms.get("pending", 0) > 0 else "normal")
    if cur != prev:
        timeline2.append((el, cur))
        print("    t=%6.1fs  %s → %s" % (el, prev or "(初始)", cur))
        prev = cur
    if cur == "normal" and el > 50:
        break

print()
print("  恢复时间线：")
for el, s in timeline2:
    print("    %6.1fs  %s" % (el, s))
a2n = [e for e, s in timeline2 if s == "normal"]
print()
if a2n:
    print("  Alerting → Normal：%.1f 秒" % a2n[0])
    print("  → 与 for=20s 对比，判断 Resolved 是否也受 for 约束")

# ---------- Q4: Pending 中途恢复 ----------
print("\n--- [4] Pending 中途恢复：计时是否重置 ---\n")
print("  重新切真，等进入 Pending，然后在 for 未满时切假，再看切真是否重新计时")

st, _ = req("PUT", "/api/v1/provisioning/alert-rules/" + UID,
            make_rule(UID, "vector(0)"))
print("  切真 → HTTP %s" % st)

# 等进入 pending
t0 = time.time()
got_pending = False
for i in range(20):
    time.sleep(5)
    ms = metrics_states()
    if ms.get("pending", 0) > 0:
        got_pending = True
        print("    t=%.1fs 进入 Pending" % (time.time() - t0))
        break
    if ms.get("alerting", 0) > 0:
        print("    t=%.1fs 已进入 Alerting（跳过中途恢复测试）" % (time.time() - t0))
        break

if got_pending:
    # 立刻切假（Pending 未满 20s）
    print("  进入 Pending 后立刻切假（for 未满）...")
    st, _ = req("PUT", "/api/v1/provisioning/alert-rules/" + UID,
                make_rule(UID, "vector(1)"))
    time.sleep(20)
    ms = metrics_states()
    print("    切假 20s 后：normal=%d pending=%d alerting=%d" % (
        int(ms.get("normal", 0)), int(ms.get("pending", 0)),
        int(ms.get("alerting", 0))))
    print("    → 若回到 normal，说明 Pending 计时被重置（不是累计）")

# ---------- 清理 ----------
print("\n--- [清理] ---")
st, _ = req("DELETE", "/api/v1/provisioning/alert-rules/" + UID)
print("  删除 %s → HTTP %s" % (UID, st))
time.sleep(2)
ms = metrics_states()
print("  清理后状态：")
for k in sorted(ms):
    print("    %-12s = %d" % (k, int(ms[k])))

print("\n" + "=" * 80)

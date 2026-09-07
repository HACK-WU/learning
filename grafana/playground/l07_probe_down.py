#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
7.3 最终实验：用【停 node 容器】制造真实的「机器宕机 → 数据消失」

为什么不用 pushgateway：
  Prometheus 的 scrape_configs 只有 node 和 prometheus 两个 job，
  没有配置 pushgateway，所以推进去的数据 Prometheus 抓不到（已实测确认）。

改用停容器的方案，而且这【更贴近真实】：
  真实世界里 No Data 最常见的成因就是「机器宕机 / 采集器挂了」。
  停掉 grafana-node3 就是模拟这个场景。

实验设计：
  规则：up{instance="grafana-node3:9100"} < 1  → 机器宕机则触发
  1. 建规则（noDataState=X），等进入 Normal（机器在跑）
  2. 停掉 grafana-node3 容器
  3. up 指标变成 0 → 条件成立 → 应 Pending → Alerting
  4. 再等一会儿，Prometheus 的 up 序列会因 target down 而变化
  5. 关键：容器内指标完全消失后，查询返回 No Data
  6. 观察 KeepLast 与 NoData 两种配置的差异

  ⚠️ 注意：停掉的容器会在脚本末尾【自动恢复启动】。
     这是课程环境组件，不能让它一直停着。

时间预算：约 8 分钟
"""
import json, urllib.request, urllib.error, base64, time, re, subprocess

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
FOLDER = "l07alerts"
PROM = "http://localhost:9201"
NODE3 = "grafana-node3"


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
            return e.code, {"_raw": raw[:300]}
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
              group="l07-d"):
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


def docker_stop(name):
    return subprocess.run(["docker", "stop", name],
                          capture_output=True, text=True).returncode


def docker_start(name):
    return subprocess.run(["docker", "start", name],
                          capture_output=True, text=True).returncode


def node3_up():
    """查 node3 的 up 值"""
    st, b = req("GET", '/api/v1/query?query=up{instance="grafana-node3:9100"}',
                base=PROM)
    if st == 200:
        res = (b.get("data") or {}).get("result") or []
        if res:
            return float(res[0]["value"][1])
    return None


EXPR = 'up{instance="grafana-node3:9100"}'

print("=" * 80)
print(" 7.3 最终实验：停容器造真实 No Data（KeepLast vs NoData）")
print("=" * 80)

print("\n--- [0] 前置确认 ---\n")
print("  node3 当前 up 值 = %s" % node3_up())
print("  node3 容器状态：")
print(subprocess.run(["docker", "ps", "--filter", "name=" + NODE3,
                      "--format", "{{.Names}} {{.Status}}"],
                     capture_output=True, text=True).stdout.strip())

# ---------- 实验 A：KeepLast ----------
print("\n--- [A] noDataState=KeepLast ---\n")
clean_all()
time.sleep(65)

UID = "l07-d-kl"
st, _ = req("POST", "/api/v1/provisioning/alert-rules",
            make_rule(UID, EXPR, "0s", nodata="KeepLast", execerr="KeepLast"))
print("  建规则 → HTTP %s（机器在跑时应为 Normal）" % st)

for i in range(14):
    time.sleep(10)
    ms = metrics_states()
    if sum(1 for v in ms.values() if v > 0) > 0:
        print("    t=%3ds 状态：%s" % ((i + 1) * 10,
              {k: int(v) for k, v in ms.items() if v > 0}))
        break

print("\n  停掉 %s（模拟机器宕机）..." % NODE3)
rc = docker_stop(NODE3)
print("  docker stop → rc=%s" % rc)

print("\n  观察 150s（每 15s），记录状态与 up 值：")
for i in range(10):
    time.sleep(15)
    ms = metrics_states()
    up = node3_up()
    print("    t=%3ds  up=%-6s  alerting=%d normal=%d nodata=%d error=%d pending=%d" % (
        (i + 1) * 15, up, int(ms.get("alerting", 0)), int(ms.get("normal", 0)),
        int(ms.get("nodata", 0)), int(ms.get("error", 0)),
        int(ms.get("pending", 0))))

req("DELETE", "/api/v1/provisioning/alert-rules/" + UID)
print("\n  恢复 %s..." % NODE3)
docker_start(NODE3)
time.sleep(75)

# ---------- 实验 B：NoData ----------
print("\n--- [B] 对照：noDataState=NoData ---\n")
print("  node3 up = %s（应已恢复为 1）" % node3_up())

UID2 = "l07-d-nd"
st, _ = req("POST", "/api/v1/provisioning/alert-rules",
            make_rule(UID2, EXPR, "0s", nodata="NoData", execerr="Error"))
print("  建规则 → HTTP %s" % st)

for i in range(14):
    time.sleep(10)
    ms = metrics_states()
    if sum(1 for v in ms.values() if v > 0) > 0:
        print("    t=%3ds 状态：%s" % ((i + 1) * 10,
              {k: int(v) for k, v in ms.items() if v > 0}))
        break

print("\n  停掉 %s..." % NODE3)
docker_stop(NODE3)

print("\n  观察 150s（每 15s）：")
for i in range(10):
    time.sleep(15)
    ms = metrics_states()
    up = node3_up()
    print("    t=%3ds  up=%-6s  alerting=%d normal=%d nodata=%d error=%d pending=%d" % (
        (i + 1) * 15, up, int(ms.get("alerting", 0)), int(ms.get("normal", 0)),
        int(ms.get("nodata", 0)), int(ms.get("error", 0)),
        int(ms.get("pending", 0))))

req("DELETE", "/api/v1/provisioning/alert-rules/" + UID2)
print("\n  恢复 %s..." % NODE3)
docker_start(NODE3)
time.sleep(75)

# ---------- annotations ----------
print("\n--- [C] annotations 状态标签 ---\n")
st, b = req("GET", "/api/annotations?type=alert&limit=25")
if isinstance(b, list):
    seq = sorted(b, key=lambda x: x.get("time") or 0)
    print("  最近 14 条：")
    for a in seq[-14:]:
        t = a.get("time")
        ts = time.strftime('%H:%M:%S', time.localtime(t / 1000)) if t else "?"
        print("    %s  %-26s <- %s" % (ts, a.get("newState"), a.get("prevState")))

# ---------- 清理与恢复确认 ----------
print("\n--- [清理 + 环境恢复确认] ---")
n = clean_all()
print("  清理 %d 条规则" % n)
print("  node3 容器状态：")
print("    " + subprocess.run(["docker", "ps", "--filter", "name=" + NODE3,
                               "--format", "{{.Names}} {{.Status}}"],
                              capture_output=True, text=True).stdout.strip())
print("  node3 up 值 = %s" % node3_up())
time.sleep(60)
print("  最终告警状态：")
for k in sorted(metrics_states()):
    print("    %-12s = %d" % (k, int(metrics_states()[k])))

print("\n" + "=" * 80)

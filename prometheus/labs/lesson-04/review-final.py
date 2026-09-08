#!/usr/bin/env python3
# Learner 视角最终验收：严格按讲义第四幕的命令逐字执行，不依赖任何已有状态
# 铁律：每条判定先跑再判，不凭记忆
import json
import subprocess
import time
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"
FAILS = []


def out(s=""):
    print(s, flush=True)


def sh(cmd, check=True):
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and p.returncode != 0:
        out("  [FAIL rc=%d] %s" % (p.returncode, cmd))
        out("  stderr: %s" % p.stderr[:300])
        FAILS.append("命令失败: %s" % cmd[:80])
    return p


def q(expr):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]


def api(path):
    with urllib.request.urlopen(BASE + path, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def fault(path):
    code = ("import urllib.request;"
            "print(urllib.request.urlopen('http://localhost:8080/fault/%s').read().decode())" % path)
    p = subprocess.run(["docker", "exec", "l4-app", "python3", "-c", code],
                       capture_output=True, text=True)
    return p.stdout.strip()


out("#" * 72)
out("# Learner 视角验收：讲义第四幕命令逐字可跑性检查")
out("#" * 72)

# ---- 步骤 2：四组存在且都在推进 ----
out()
out("=== 步骤 2：四个组都在，且都有求值耗时 ===")
durs = q("prometheus_rule_group_last_duration_seconds")
names = sorted(r["metric"].get("rule_group", "?").split(";")[-1] for r in durs)
out("  组: %s" % names)
expect = ["l4-A-slow", "l4-B-fast", "l4-C-recording", "l4-D-alerts"]
if names == expect:
    out("  ✅ 四组齐全")
else:
    FAILS.append("步骤2: 组列表不符，期望 %s 实测 %s" % (expect, names))

# ---- 步骤 3：targets 可读 ----
out()
out("=== 步骤 3：/api/v1/targets 可读，两个 job 都在 ===")
tg = api("/api/v1/targets")["data"]["activeTargets"]
jobs = sorted(set(t.get("labels", {}).get("job", "?") for t in tg))
out("  jobs: %s" % jobs)
if set(["l4-demo", "prometheus"]).issubset(set(jobs)):
    out("  ✅ 两个 job 都在（含自抓取，这是本课所有内部指标的前提）")
else:
    FAILS.append("步骤3: job 列表不符: %s" % jobs)

# ---- 步骤 4：recording rule 产物存在 ----
out()
out("=== 步骤 4：recording rule 产物 job:app_requests_error:ratio1m 可查 ===")
r = q("job:app_requests_error:ratio1m")
out("  返回 %d 条" % len(r))
if r:
    out("  ✅ 可查，值 = %s" % r[0]["value"][1])
else:
    FAILS.append("步骤4: job:app_requests_error:ratio1m 查不到")

r = q("job:app_requests:rate1m")
out("  job:app_requests:rate1m 返回 %d 条" % len(r))
if not r:
    FAILS.append("步骤4: job:app_requests:rate1m 查不到")

# ---- 步骤 6/8：告警状态机可推进 ----
out()
out("=== 步骤 6/8：告警状态机可从无 → pending/firing ===")
fault("off")
out("  已 off，等 65 秒清空历史")
time.sleep(65)
a = {x["labels"].get("alertname"): x["state"] for x in api("/api/v1/alerts")["data"]["alerts"]}
out("  清空后: %s" % (a if a else "(无告警)"))
if a:
    out("  ⚠️ 清空后仍有告警，步骤 6 的'干净起点'可能不成立")

out()
fault("on?rate=0.5")
out("  已注入 50%% 错误率")
for wait, label in [(12, "第一次采样"), (22, "第二次采样")]:
    time.sleep(wait)
    a = {x["labels"].get("alertname"): x["state"] for x in api("/api/v1/alerts")["data"]["alerts"]}
    out("  %s: %s" % (label, a))

if not a:
    FAILS.append("步骤6: 注入故障后无任何告警，状态机未推进")
else:
    out("  ✅ 状态机可推进")

# ---- 步骤 7：wobble 端点可用 ----
out()
out("=== 步骤 7：wobble 端点可用 ===")
r = fault("wobble?center=0.075&period=120&amp=0.06")
out("  %s" % r)
if '"ok": true' in r or '"ok":true' in r.replace(" ", ""):
    out("  ✅ wobble 端点可用")
else:
    FAILS.append("步骤7: wobble 端点返回异常: %s" % r[:100])

# ---- 步骤 8：keep_firing_for 规则在 ----
out()
out("=== 步骤 8：keep_firing_for 规则存在 ===")
rules = api("/api/v1/rules")["data"]["groups"]
found = False
for g in rules:
    for r in g.get("rules", []):
        if r.get("name") == "L4ErrorRateKeepFiring":
            found = True
            out("  找到: %s  keepFiringFor=%s" % (r.get("name"), r.get("keepFiringFor")))
if found:
    out("  ✅ keep_firing_for 规则在")
else:
    FAILS.append("步骤8: 未找到 L4ErrorRateKeepFiring 规则")

out()
out("#" * 72)
out("# Learner 验收结束")
out("#" * 72)
out()
out("P0: %d" % len(FAILS))
for f in FAILS:
    out("  ❌ %s" % f)
if not FAILS:
    out("✅ 讲义第四幕全部命令可跑通")

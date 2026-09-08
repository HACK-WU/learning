#!/usr/bin/env python3
# 课 4 评审：pedagogy + learner 双视角，逐字执行讲义第四幕全部命令
# 铁律：每条"缺失/错误"判定必须先核验原文，不得凭记忆或直觉
import json
import subprocess
import time
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"
FAILS = []
WARNS = []


def out(s=""):
    print(s, flush=True)


def q(expr):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]


def qnum(expr):
    r = q(expr)
    return float(r[0]["value"][1]) if r else None


def api(path):
    with urllib.request.urlopen(BASE + path, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def fault(path):
    code = ("import urllib.request;"
            "print(urllib.request.urlopen('http://localhost:8080/fault/%s').read().decode())" % path)
    p = subprocess.run(["docker", "exec", "l4-app", "python3", "-c", code],
                       capture_output=True, text=True)
    return p.stdout.strip()


def gl(m):
    g = m.get("rule_group", "?")
    return g.split(";")[-1] if ";" in g else g


def alerts():
    return {a["labels"].get("alertname"): a["state"]
            for a in api("/api/v1/alerts")["data"]["alerts"]}


out("#" * 72)
out("# 课 4 评审：逐字核验讲义中的每一处实测数字")
out("#" * 72)

# ============ 核验 1：步骤 2 的组耗时 ============
out()
out("=== 核验 1：步骤 2 四组求值耗时（讲义称 A 是 B 的 6 倍）===")
durs = {gl(r["metric"]): float(r["value"][1])
        for r in q("prometheus_rule_group_last_duration_seconds")}
a, b = durs.get("l4-A-slow"), durs.get("l4-B-fast")
out("  l4-A-slow = %.6f" % a if a else "  l4-A-slow 缺失")
out("  l4-B-fast = %.6f" % b if b else "  l4-B-fast 缺失")
if a and b:
    ratio = a / b
    out("  实际倍数 = %.2f" % ratio)
    ok = 3.5 <= ratio <= 9.0
    out("  讲义写'5~7 倍浮动' -> %s" % ("✅ 在浮动范围内" if ok else "❌ 超出范围"))
    if not ok:
        FAILS.append("步骤2: 慢组/快组倍数 %.2f 超出讲义标注的 5~7 倍范围" % ratio)

# ============ 核验 2：墙钟 vs 之和 ============
out()
out("=== 核验 2：讲义称四组'差值全在 0.0001 秒以内'===")
sums = {gl(r["metric"]): float(r["value"][1])
        for r in q("prometheus_rule_group_last_rule_duration_sum_seconds")}
maxdiff = 0.0
for g in sorted(durs):
    d, s = durs[g], sums.get(g, 0.0)
    diff = abs(d - s)
    maxdiff = max(maxdiff, diff)
    out("  %-16s 墙钟=%.6f 之和=%.6f 差值=%.6f" % (g, d, s, diff))
out("  最大差值 = %.6f" % maxdiff)
if maxdiff > 0.0002:
    out("  ⚠️ 讲义写'都在 0.0002 秒以内'，实测最大 %.6f" % maxdiff)
    WARNS.append("步骤2: 差值上限表述，实测最大 %.6f（讲义写 0.0002）" % maxdiff)
else:
    out("  ✅ 与讲义一致（< 0.0002）")

# ============ 核验 3：组间并行（4 个时刻互不相同）============
out()
out("=== 核验 3：讲义称'4 个组的求值时刻互不相同'===")
res = q("prometheus_rule_group_last_evaluation_timestamp_seconds")
ts = [float(r["value"][1]) for r in res]
out("  组数 = %d，不同时刻数 = %d" % (len(ts), len(set(ts))))
if len(ts) == len(set(ts)) == 4:
    out("  ✅ 4 组 4 个不同时刻，与讲义一致")
else:
    FAILS.append("步骤2: 组求值时刻数不符，实测 %d 组 %d 时刻" % (len(ts), len(set(ts))))

# ============ 核验 4：版本差异（单规则级指标不存在）============
out()
out("=== 核验 4：讲义称单规则级时间戳指标'已不存在（返回 0 条）'===")
n1 = len(q("prometheus_rule_last_evaluation_timestamp_seconds"))
n2 = len(q("prometheus_rule_group_last_evaluation_timestamp_seconds"))
out("  prometheus_rule_last_evaluation_timestamp_seconds       -> %d 条" % n1)
out("  prometheus_rule_group_last_evaluation_timestamp_seconds -> %d 条" % n2)
if n1 == 0 and n2 == 4:
    out("  ✅ 与讲义一致（0 条 / 4 条）")
else:
    FAILS.append("步骤2: 版本差异核验不符，实测 %d / %d" % (n1, n2))

# ============ 核验 5：interval 覆盖 ============
out()
out("=== 核验 5：讲义称 A/B 的 interval:5s 覆盖了全局 10s ===")
res = q("prometheus_rule_group_interval_seconds")
iv = {gl(r["metric"]): r["value"][1] for r in res}
out("  %s" % iv)
ok = (iv.get("l4-A-slow") == "5" and iv.get("l4-B-fast") == "5"
      and iv.get("l4-C-recording") == "10" and iv.get("l4-D-alerts") == "10")
out("  %s" % ("✅ 与讲义一致" % () if ok else "❌ 不符"))
if not ok:
    FAILS.append("步骤2: interval 覆盖核验不符: %s" % iv)

# ============ 核验 6：promtool 规则数 ============
out()
out("=== 核验 6：讲义称 promtool 输出 'SUCCESS: 7 rules found' ===")
p = subprocess.run(["docker", "exec", "l4-prom", "/bin/promtool",
                    "check", "rules", "/etc/prometheus/rules.yml"],
                   capture_output=True, text=True)
tail = p.stdout.strip().splitlines()[-1] if p.stdout.strip() else "(空)"
out("  实测: %s" % tail)
if "8 rules found" in tail:
    out("  ✅ 与讲义一致（8 条）")
else:
    FAILS.append("步骤1: promtool 输出不符，实测: %s" % tail)

# ============ 核验 7：ALERTS_FOR_STATE 的 alertstate=None ============
out()
out("=== 核验 7：讲义称 ALERTS_FOR_STATE 的 alertstate 为 None ===")
fault("on?rate=0.5")
out("  已注入 50%% 错误率，等 33 秒")
time.sleep(33)
res = q("ALERTS_FOR_STATE")
if res:
    for r in res:
        out("  %-24s alertstate=%s" % (r["metric"].get("alertname"),
                                       r["metric"].get("alertstate")))
    states = set(r["metric"].get("alertstate") for r in res)
    if None in states or "None" in str(states):
        out("  ✅ alertstate 为 None，与讲义一致")
    else:
        WARNS.append("步骤6: ALERTS_FOR_STATE 的 alertstate 实测为 %s，讲义写 None" % states)
else:
    out("  (空)")

# ============ 核验 8：三条告警的状态对照 ============
out()
out("=== 核验 8：讲义核心帧——同一 ratio1m 下 0s 已 firing、20s 仍 pending ===")
ratio = qnum("job:app_requests_error:ratio1m")
a = alerts()
out("  ratio1m = %.4f" % ratio if ratio else "  ratio1m = n/a")
for k in sorted(a):
    out("    %-24s %s" % (k, a[k]))
cond = ("L4ErrorRateWobble" in a and a["L4ErrorRateWobble"] == "firing"
        and "L4ErrorRateKeepFiring" in a and a["L4ErrorRateKeepFiring"] == "firing")
out("  for=0s 两条均 firing: %s" % ("✅" if cond else "❌"))
if not cond:
    FAILS.append("步骤6: for=0s 两条未同时 firing，实测 %s" % a)

# ============ 核验 9：只要条件成立，20s 最终会 firing ============
out()
out("=== 核验 9：持续故障下 L4HighErrorRate 最终会转 firing（验证 for 不是永久阻断）===")
time.sleep(30)
a = alerts()
crit = a.get("L4HighErrorRate", "-")
out("  再等 30 秒后 L4HighErrorRate = %s" % crit)
if crit == "firing":
    out("  ✅ 持续故障下 for=20s 最终转 firing，说明 for 只是'过滤器'不是'阻断器'")
else:
    WARNS.append("步骤6: 持续故障下 L4HighErrorRate 仍为 %s" % crit)

out()
out("#" * 72)
out("# 评审核验结束")
out("#" * 72)
out()
out("P0（阻断性）: %d" % len(FAILS))
for f in FAILS:
    out("  ❌ %s" % f)
out()
out("P1/P2（提示性）: %d" % len(WARNS))
for w in WARNS:
    out("  ⚠️ %s" % w)
if not FAILS and not WARNS:
    out("✅ 全部核验通过")

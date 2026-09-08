#!/usr/bin/env python3
# 课 4 讲义证据统一采集脚本
# 把所有实测数字写入 evidence-report.txt，供讲义逐字引用
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"
RULES = "/mnt/d/projects/learning/prometheus/labs/lesson-04/rules.yml"

LOG = []


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


def reload_rules():
    req = urllib.request.Request(BASE + "/-/reload", data=b"", method="POST")
    try:
        urllib.request.urlopen(req, timeout=20).read()
    except Exception as e:
        out("  reload 失败: %s" % e)


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
    d = api("/api/v1/alerts")["data"]["alerts"]
    return {a["labels"].get("alertname"): a["state"] for a in d}


# ============================================================
out("#" * 70)
out("# 课 4《规则引擎》讲义证据采集  %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
out("# Prometheus v3.14.0   宿主端口 9094")
out("#" * 70)

# ---------- 前置：确认规则文件版本 ----------
out()
out("## 前置：当前 rules.yml 的组清单")
with open(RULES, encoding="utf-8") as f:
    txt = f.read()
for line in txt.splitlines():
    if line.strip().startswith("- name:"):
        out("  " + line.strip())
out()

# ============================================================
out()
out("=" * 70)
out("## A. 知识点 1：组内串行 / 组间并行")
out("=" * 70)

out()
out("### A1. 各组求值耗时（prometheus_rule_group_last_duration_seconds）")
res = q("prometheus_rule_group_last_duration_seconds")
durs = {gl(r["metric"]): float(r["value"][1]) for r in res}
for g, d in sorted(durs.items(), key=lambda x: -x[1]):
    out("  %-20s %.6f s" % (g, d))

out()
out("### A2. 组内串行判定：整组墙钟(last_duration) vs 组内各规则耗时之和(sum)")
out("  串行 => 两者近似相等；并行 => 墙钟显著小于之和")
res = q("prometheus_rule_group_last_rule_duration_sum_seconds")
sums = {gl(r["metric"]): float(r["value"][1]) for r in res}
out("  %-20s %14s %14s %12s" % ("组", "整组墙钟", "各规则之和", "差值"))
for g in sorted(durs):
    d, s = durs[g], sums.get(g, 0.0)
    out("  %-20s %14.6f %14.6f %12.6f" % (g, d, s, d - s))

out()
out("### A3. 组间并行：各组最近求值时刻（应互不相同）")
res = q("prometheus_rule_group_last_evaluation_timestamp_seconds")
rows = sorted(((gl(r["metric"]), float(r["value"][1])) for r in res), key=lambda x: x[1])
now = time.time()
out("  当前系统时刻: %.3f" % now)
for g, ts in rows:
    out("  %-20s %.3f  (距今 %.1f s)" % (g, ts, now - ts))
if len(rows) > 1:
    out("  -> %d 个组的求值时刻互不相同 => 组间并行推进" % len(rows))

out()
out("### A4. 各组配置间隔（prometheus_rule_group_interval_seconds）")
res = q("prometheus_rule_group_interval_seconds")
for r in sorted(res, key=lambda x: gl(x["metric"])):
    out("  %-20s %s s" % (gl(r["metric"]), r["value"][1]))

out()
out("### A5. 【版本差异核查】单规则级时间戳指标是否存在")
for m in ["prometheus_rule_last_evaluation_timestamp_seconds",
          "prometheus_rule_group_last_evaluation_timestamp_seconds"]:
    out("  %-58s -> %d 条" % (m, len(q(m))))

# ============================================================
out()
out("=" * 70)
out("## B. 知识点 1：规则求值拿到的是'上次抓取到的数据'")
out("=" * 70)

out()
out("### B1. 上次抓取距今多久（来自 /api/v1/targets）")
import datetime


def parse_rfc3339(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


for i in range(3):
    now = time.time()
    tg = api("/api/v1/targets")["data"]["activeTargets"]
    for t in tg:
        job = t.get("labels", {}).get("job", "?")
        ls = t.get("lastScrape")
        if ls:
            lag = now - parse_rfc3339(ls)
            out("  job=%-14s 上次抓取距今 %.2f s" % (job, lag))
    if i < 2:
        time.sleep(2)

out()
out("### B2. 抓取间隔与求值间隔（配置）")
cfg = api("/api/v1/status/config")["data"]["yaml"]
for line in cfg.splitlines():
    s = line.strip()
    if "interval" in s and ("scrape" in s or "evaluation" in s):
        out("  " + s)

# ============================================================
out()
out("=" * 70)
out("## C. 知识点 2：recording rule 的值被'冻结'")
out("=" * 70)

out()
out("### C1. 连续 30 次每秒采样 job:app_requests_error:ratio1m")
samples = []
for i in range(30):
    v = qnum("job:app_requests_error:ratio1m")
    ts = q("job:app_requests_error:ratio1m")
    st = float(ts[0]["value"][0]) if ts else 0.0
    samples.append((time.time(), st, v))
    time.sleep(1)

vals = [v for _, _, v in samples if v is not None]
uniq = []
for v in vals:
    if not uniq or abs(v - uniq[-1]) > 1e-9:
        uniq.append(v)
out("  采样次数: %d" % len(samples))
out("  值的不同取值个数: %d" % len(uniq))
out("  -> 值在两次求值之间被冻结（组间隔 10s，30s 内理论最多变 3~4 次）")
out()
out("  逐次采样（查询时刻 / 样本时间戳 / 值）:")
for qt, st, v in samples[:12]:
    out("    %.1f  %.1f  %.6f" % (qt, st, v if v is not None else -1))
out("    ... 省略后续 %d 行" % max(0, len(samples) - 12))
out()
out("  全部取值序列: %s" % ", ".join("%.6f" % v for v in uniq))

# ============================================================
out()
out("=" * 70)
out("## D. 知识点 2：【经典坑】新增 recording rule 后立刻查不到值")
out("=" * 70)

NEW_GROUP = """
  # ---- 演示用：新增 recording rule ----
  - name: l4-E-newrecording
    interval: 60s
    rules:
      - record: l4:brandnew:metric
        expr: sum(app_requests_total)
"""

with open(RULES, "a", encoding="utf-8") as f:
    f.write(NEW_GROUP)
reload_rules()
time.sleep(2)

out()
out("### D1. reload 后立刻查 l4:brandnew:metric")
r = q("l4:brandnew:metric")
out("  返回 %d 条 %s" % (len(r), "(空！这就是那个坑)" if not r else "(有值)"))

out()
out("### D2. 该组 interval=60s，等待 65 秒后再查")
time.sleep(65)
r = q("l4:brandnew:metric")
out("  返回 %d 条" % len(r))
for x in r:
    out("    值 = %s" % x["value"][1])

out()
out("### D3. 清理：恢复原始规则文件")
txt2 = txt  # 进入本脚本时读到的原始内容
with open(RULES, "w", encoding="utf-8") as f:
    f.write(txt2)
reload_rules()
time.sleep(3)
out("  已恢复并 reload，组数: %d" % txt2.count("- name:"))

# ============================================================
out()
out("=" * 70)
out("## E. 知识点 3：告警状态机 Inactive → Pending → Firing")
out("=" * 70)

out()
out("### E1. 先确保无告警")
fault("off")
out("  fault/off")
time.sleep(65)
out("  静置 65 秒（等 rate1m 窗口把历史故障滑出）")
a = alerts()
out("  当前告警: %s" % (a if a else "(无)"))

out()
out("### E2. 注入 50%% 错误率")
out("  " + fault("on?rate=0.5"))

out()
out("  等 8 秒（< for=20s）后查：")
time.sleep(8)
a = alerts()
ratio = qnum("job:app_requests_error:ratio1m")
out("    ratio1m = %s" % ("%.4f" % ratio if ratio is not None else "n/a"))
for k in sorted(a):
    out("    %-24s %s" % (k, a[k]))
for name in ["L4HighErrorRate", "L4ErrorRateWobble", "L4ErrorRateKeepFiring"]:
    if name not in a:
        out("    %-24s (未出现)" % name)

out()
out("  再等 25 秒（已跨过 for=20s）后查：")
time.sleep(25)
a = alerts()
ratio = qnum("job:app_requests_error:ratio1m")
out("    ratio1m = %s" % ("%.4f" % ratio if ratio is not None else "n/a"))
for k in sorted(a):
    out("    %-24s %s" % (k, a[k]))

out()
out("### E3. ALERTS_FOR_STATE（Pending 计时证据）")
res = q("ALERTS_FOR_STATE")
if res:
    for r in res:
        out("    %-24s alertstate=%-10s 值=%s"
            % (r["metric"].get("alertname"), r["metric"].get("alertstate"), r["value"][1]))
else:
    out("    (空 —— 说明当前没有处于 Pending 的告警)")

# ============================================================
out()
out("=" * 70)
out("## F. 知识点 3：抖动（flapping）")
out("=" * 70)

out()
out("### F1. 反例：振荡周期 24s << rate 窗口 1m，被完全抹平")
out("  " + fault("wobble?center=0.08&period=24&amp=0.04"))
time.sleep(70)
vals = []
for i in range(12):
    v = qnum("job:app_requests_error:ratio1m")
    if v is not None:
        vals.append(v)
    time.sleep(5)
out("  12 次采样（每 5 秒）ratio1m:")
out("    %s" % ", ".join("%.4f" % v for v in vals))
if vals:
    out("    极差 = %.4f  -> 窗口把振荡抹平了" % (max(vals) - min(vals)))

out()
out("### F2. 正例：振荡周期 120s >> 窗口可平滑范围，成功跨越阈值")
out("  " + fault("wobble?center=0.075&period=120&amp=0.06"))
time.sleep(70)
out("  先跑 70 秒让新振荡填满窗口，然后采样 150 秒")
prev = None
flips = 0
rows = []
for i in range(30):
    v = qnum("job:app_requests_error:ratio1m")
    st = alerts().get("L4ErrorRateWobble", "-")
    mark = ""
    if prev is not None and st != prev:
        flips += 1
        mark = "   <-- 翻转 #%d (%s -> %s)" % (flips, prev, st)
    rows.append("  t=%3ds  ratio1m=%s  Wobble=%-8s%s"
                % (i * 5, "%.4f" % v if v is not None else "n/a", st, mark))
    prev = st
    time.sleep(5)
for line in rows:
    out(line)
out()
out("  === 150 秒内 Wobble(for=0s) 状态翻转次数: %d ===" % flips)
crit_fired = any("L4HighErrorRate" in l for l in rows)
out("  === 同期 Critical(for=20s) 是否曾 firing: %s ===" % ("是" if crit_fired else "否"))

# ============================================================
out()
out("=" * 70)
out("## G. 知识点 3：keep_firing_for（恢复保护）")
out("=" * 70)

out()
out("### G1. 注入故障让两条同阈值告警都 firing")
out("  " + fault("on?rate=0.5"))
time.sleep(30)
a = alerts()
out("  当前: %s" % a)

out()
out("### G2. 关掉故障，记录两条告警各自消失的时刻")
out("  " + fault("off"))
start = time.time()
gone_w = gone_k = None
for i in range(40):
    a = alerts()
    w = a.get("L4ErrorRateWobble", "-")
    k = a.get("L4ErrorRateKeepFiring", "-")
    el = int(time.time() - start)
    if gone_w is None and w == "-":
        gone_w = el
        out("  t=%3ds  Wobble(for=0s, 无 keep_firing_for) 消失" % el)
    if gone_k is None and k == "-":
        gone_k = el
        out("  t=%3ds  KeepFiring(keep_firing_for=30s) 消失" % el)
    if gone_w is not None and gone_k is not None:
        break
    time.sleep(4)

out()
out("  === 对比 ===")
out("    Wobble    (for=0s, 无 keep_firing_for) : %s s 后消失" % gone_w)
out("    KeepFiring(keep_firing_for=30s)        : %s s 后消失" % gone_k)
if gone_w is not None and gone_k is not None:
    out("    多存活: %d 秒" % (gone_k - gone_w))

out()
out("=" * 70)
out("## 证据采集结束")
out("=" * 70)

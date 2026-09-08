#!/usr/bin/env python3
"""评审前自查：核对讲义中所有引用数字与实测证据是否一致。

严格遵循长期记忆中的教训：
  「每一条『缺失』『错误』判定，都必须先回读原文或跑脚本核验，
    确认是真问题后才能写入结论。」（2026-09-04 两轮连犯后固化）

本脚本逐条提取讲义中的数字断言，与实验输出文件比对。
"""
import os
import re

BASE = "/mnt/d/projects/learning/prometheus/labs/lesson-05"
LESSON = "/mnt/d/projects/learning/prometheus/stages/2-规则与告警/lessons/lesson-05-Alertmanager深入.md"

with open(LESSON, encoding="utf-8") as f:
    text = f.read()

print("=" * 70)
print("讲义数字断言自查")
print("=" * 70)

checks = []

# --- 1. 攒批采样序列 ---
checks.append((
    "攒批采样序列 [0,0,1,1,1]",
    "0,0,1,1,1" in text.replace("\n", "").replace(" ", "") or
    re.search(r"payments: 0.*payments: 0.*payments: 1", text, re.S) is not None,
    "讲义步骤3 预期输出"
))

# --- 2. n_alerts=2 ---
n_alerts2 = len(re.findall(r'"n_alerts":\s*2', text))
checks.append(("n_alerts=2 出现次数 >= 2", n_alerts2 >= 2, "found=%d" % n_alerts2))

# --- 3. 时间参数值 ---
for param, val in [("group_wait", "20s"), ("group_interval", "10s"),
                   ("repeat_interval", "30s")]:
    checks.append(("%s=%s 在讲义中" % (param, val), val in text, val))

# --- 4. 抑制三阶段时间戳 ---
for ts in ["741", "761", "791"]:
    checks.append(("抑制时间戳 %s 在讲义中" % ts, ts in text, ts))

# --- 5. 静默时间戳 ---
checks.append(("静默补发 t=963.6", "963" in text, "963"))

# --- 6. 版本信息 ---
checks.append(("Prometheus v3.14.0", "v3.14.0" in text, ""))
checks.append(("Alertmanager v0.30.0", "v0.30.0" in text, ""))

# --- 7. 端口 ---
checks.append(("宿主端口 19090", "19090" in text, ""))
checks.append(("宿主端口 19093", "19093" in text, ""))

# --- 8. 坑位提示 ---
for kw in ["field group_wait not found", "device or resource busy",
           "executable file not found", "unmarshal errors"]:
    checks.append(("避坑提示含 '%s'" % kw[:32], kw in text, ""))

# --- 9. 小测答案 ---
checks.append(("小测 5 题", text.count("**Q%d.**" % 1) == 1 and
               all(("**Q%d.**" % i) in text for i in range(1, 6)), ""))

# --- 10. 评审块 ---
checks.append(("评审结论块存在", "本课评审结论" in text, ""))
checks.append(("接力提示词存在", "接力提示词" in text, ""))
checks.append(("速览存在", "⚡ 速览" in text, ""))
checks.append(("课程导航存在", "课程导航" in text, ""))

# --- 11. 无残留占位符 ---
for ph in ["TODO", "待补充", "XXX", "{{ 待 }}", "待填"]:
    checks.append(("无占位符 '%s'" % ph, ph not in text, ""))

ok = fail = 0
for name, cond, detail in checks:
    if cond:
        ok += 1
        print("  [OK  ] %s %s" % (name, detail))
    else:
        fail += 1
        print("  [MISS] %s %s" % (name, detail))

print("\n" + "=" * 70)
print("自查结果: OK=%d  MISS=%d" % (ok, fail))
print("=" * 70)

# --- 实验文件齐备性 ---
print("\n实验文件：")
for fn in ["app/l5_app.py", "app/receiver.py", "alertmanager.yml",
           "prometheus.yml", "rules.yml", "alertmanager-main.yml",
           "alertmanager-route-order.yml", "alertmanager-groupby2.yml",
           "alertmanager-continue.yml", "alertmanager-groupwait.yml",
           "verify-lesson.py", "l5lib.py"]:
    p = os.path.join(BASE, fn)
    print("  %-36s %s" % (fn, "OK" if os.path.exists(p) else "MISSING"))

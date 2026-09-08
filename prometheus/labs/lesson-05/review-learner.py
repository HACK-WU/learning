#!/usr/bin/env python3
"""课 5 双视角评审 - learner（学习者）视角。

核心判据：假设读者是**只拿到这份讲义、没有本次对话上下文**的人，
他能不能照着跑通、看懂、不踩坑。

重点检查：
  1. 环境依赖是否交代（Docker/WSL/镜像/端口）
  2. 引用的外部文件是否都真实存在
  3. 每个"预期输出"是否可能因时序/环境差异而复现失败
  4. 命令是否可在读者机器上直接执行（不依赖本课临时产物）
  5. 术语是否首次出现时有解释
"""
import os
import re

LESSON = ("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/"
          "lessons/lesson-05-Alertmanager深入.md")
BASE = "/mnt/d/projects/learning/prometheus/labs/lesson-05"
with open(LESSON, encoding="utf-8") as f:
    text = f.read()

issues = []
notes = []

# ---------- 1. 环境交代 ----------
for kw in ["WSL", "Docker", "v3.14.0", "v0.30.0", "python:3.12-slim"]:
    if kw not in text:
        issues.append(("P1", "未交代环境依赖: %s" % kw))
notes.append("① 环境依赖交代: %s" % ("齐全" if not [
    i for i in issues if i[1].startswith("未交代")] else "缺失"))

# ---------- 2. 引用的外部文件是否真实存在 ----------
refs = re.findall(r"`(labs/lesson-05/[\w/\.\-]+)`", text)
notes.append("② 引用文件 %d 个" % len(refs))
for r in set(refs):
    p = os.path.join("/mnt/d/projects/learning/prometheus", r)
    if not os.path.exists(p):
        issues.append(("P0", "引用的文件不存在: %s" % r))
    else:
        notes.append("② OK: %s" % r)

# ---------- 3. 内部锚点链接（同目录 md） ----------
md_links = re.findall(r"\]\(([\w\-]+\.md)\)", text)
for l in set(md_links):
    p = os.path.join("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/lessons", l)
    notes.append("③ 链接 %s: %s" % (l, "OK" if os.path.exists(p) else "MISSING"))
    if not os.path.exists(p):
        issues.append(("P1", "同目录链接失效: %s" % l))

# ---------- 4. 时序敏感点（最容易让读者复现失败） ----------
# 注意：步骤 3 的 sleep 3/4/5 是攒批实验的"错时注入"与"密集采样循环"，
# 属故意设计，不是等待窗口 —— 粗放地检查所有 sleep < 15s 会误判。
# 只检查"注入/恢复后立即等待结果"的场景（sleep 后紧跟查询命令）。
risks = []
for m in re.finditer(r"sleep (\d+)\s*\n(?:.*\n){0,2}?\s*docker exec[^\n]*count",
                     text):
    v = int(m.group(1))
    if v < 15:
        risks.append(v)
notes.append("④ 等待后立即查询的 sleep: %s" % (risks if risks else "无过短项"))
if risks:
    issues.append(("P1", "有 %d 处 sleep(%s) 后立刻查询，group_wait=20s 下不够"
                   % (len(risks), risks)))

# ---------- 5. 术语首次出现是否解释 ----------
terms = ["抑制", "静默", "分组", "路由树", "commonLabels", "group_wait",
         "repeat_interval", "group_interval", "continue"]
for t in terms:
    if t not in text:
        issues.append(("P1", "术语 '%s' 全文未出现" % t))
notes.append("⑤ 关键术语覆盖: %d/%d" % (
    sum(1 for t in terms if t in text), len(terms)))

# ---------- 6. 是否有"读者照抄会卡住"的省略 ----------
for pat in ["（略）", "（此处省略", "同上)", "参照上文", "自行替换"]:
    if pat in text:
        issues.append(("P0", "含省略/含糊表述: %s" % pat))

# ---------- 7. 避坑提示是否覆盖本课新坑 ----------
pits = {
    "app 无 wget": "executable file not found",
    "group_wait 字段位置": "field group_wait not found",
    "bind mount 不能 cp": "device or resource busy",
}
for name, kw in pits.items():
    ok = kw in text
    notes.append("⑥ 避坑 '%s': %s" % (name, "已覆盖" if ok else "缺失"))
    if not ok:
        issues.append(("P1", "避坑提示缺失: %s" % name))

# ---------- 8. 端口冲突提醒 ----------
notes.append("⑦ 端口提醒: %s" % ("有" if "19090" in text and "占用" in text else "缺失"))
if "占用" not in text:
    issues.append(("P1", "未提醒端口可能被占用"))

print("=" * 70)
print("双视角评审 - learner（学习者）视角")
print("=" * 70)
for n in notes:
    print("  %s" % n)
print()
if not issues:
    print("  ✅ 无问题")
else:
    p0 = [i for i in issues if i[0] == "P0"]
    p1 = [i for i in issues if i[0] == "P1"]
    print("  P0: %d   P1: %d" % (len(p0), len(p1)))
    for sev, d in issues:
        print("   [%s] %s" % (sev, d))
print("=" * 70)

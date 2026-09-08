#!/usr/bin/env python3
"""课 5 双视角评审 - pedagogy（教学法）视角。

按讲义交付规范（长期记忆 mem_274a28_7935395）核验：
  ① 五幕结构
  ② 六要素展开（一句话定义/直觉建立/核心原理/示例演示/常见误区/一句话记住）
  ③ 结论必须实测
  ④ 第四幕每条命令"读者照抄能跑通吗"
  ⑤ 课尾含接力提示词 + 课程导航 + 速览 + 小测
"""
import re

LESSON = ("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/"
          "lessons/lesson-05-Alertmanager深入.md")
with open(LESSON, encoding="utf-8") as f:
    text = f.read()

issues = []   # (severity, desc)
notes = []

# ---------- ① 五幕结构 ----------
five = ["第一幕", "第二幕", "第三幕", "第四幕", "第五幕"]
for a in five:
    if a not in text:
        issues.append(("P0", "缺少%s" % a))
notes.append("① 五幕结构: %s" % ("齐全" if all(a in text for a in five) else "缺失"))

# ---------- ② 六要素 ----------
six = ["一句话定义", "直觉建立", "核心原理", "示例演示", "常见误区", "一句话记住"]
for k in ["知识点 1", "知识点 2", "知识点 3"]:
    # 截取该知识点到下一个同级标题之间的内容
    m = re.search(r"^## %s.*?(?=^## (?:知识点|🧪))" % k, text, re.S | re.M)
    seg = m.group(0) if m else ""
    missing = [s for s in six if s not in seg]
    if missing:
        issues.append(("P1", "%s 缺六要素: %s" % (k, ",".join(missing))))
    notes.append("② %s 六要素: %s" % (k, "齐全" if not missing else "缺" + ",".join(missing)))

# ---------- ③ 示例演示必须有实测数据 ----------
demo_blocks = re.findall(r"### 示例演示.*?(?=###|\Z)", text, re.S)
notes.append("③ 示例演示块: %d 个" % len(demo_blocks))
for i, b in enumerate(demo_blocks, 1):
    # 输出类代码块常用无语言标注的纯文本块（放终端输出更合适），
    # 因此检测规则不能只认 ```bash —— 只认 bash 会把输出型示例误判为"缺实测数据"
    has_block = re.search(r"```(\w+)?\n", b) is not None
    has_num = re.search(r"\d", b) is not None
    # 至少要有"数值型证据"：时间戳、计数、n_alerts、百分比等
    has_evidence = bool(re.search(
        r'(t=|\[t=|n_alerts|count|payments|infra|default|\d+\.\d+s|'
        r'silenceID|state|zone-)', b))
    if not has_block:
        issues.append(("P1", "示例演示 #%d 缺少代码块" % i))
    elif not (has_num and has_evidence):
        issues.append(("P1", "示例演示 #%d 缺少实测数字/证据" % i))
    else:
        notes.append("③ 示例演示 #%d: 有代码块 + 实测证据" % i)

# ---------- ④ 第四幕命令可照抄 ----------
m4 = re.search(r"## 🧪 第四幕.*?(?=## 🎯)", text, re.S)
seg4 = m4.group(0) if m4 else ""
if not seg4:
    issues.append(("P0", "第四幕缺失"))
else:
    # 禁止的省略写法（规范硬约束）
    for bad in ["（同上）", "(同上)", "列定义同上", "此处省略", "略……"]:
        if bad in seg4:
            issues.append(("P0", "第四幕含省略写法 '%s'" % bad))
    # 每个步骤应有命令块
    steps = re.findall(r"### 步骤 (\d+)", seg4)
    notes.append("④ 第四幕步骤: %s" % ",".join(steps))
    if len(steps) < 9:
        issues.append(("P1", "第四幕步骤数 %d < 9" % len(steps)))
    # 命令块数量
    cmds = len(re.findall(r"```bash", seg4))
    notes.append("④ 第四幕 bash 代码块: %d 个" % cmds)
    if cmds < 10:
        issues.append(("P1", "第四幕 bash 块 %d 偏少" % cmds))

# ---------- ⑤ 课尾四件套 ----------
tail = ["接力提示词", "课程导航", "⚡ 速览", "本课小测"]
for t in tail:
    if t not in text:
        issues.append(("P1", "课尾缺少 '%s'" % t))
notes.append("⑤ 课尾四件套: %s" % ("齐全" if all(t in text for t in tail) else "缺失"))

# ---------- 评审结论块（对学员可见） ----------
if "本课评审结论" not in text:
    issues.append(("P0", "缺少对学员可见的评审结论块"))

# ---------- 与其他课程的一致性 ----------
if "课 4" not in text:
    issues.append(("P1", "未与课 4 衔接"))
if "课 6" not in text:
    issues.append(("P1", "未与课 6 衔接"))

# ---------- 输出 ----------
print("=" * 70)
print("双视角评审 - pedagogy（教学法）视角")
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

"""课6 讲义评审 —— learner 视角（读者照抄能否跑通）。

核心判据：假设读者只有这份文档、没有代码上下文，能否一步步跑通。

检查维度：
1. 命令的完整性与可执行性（无省略、无占位符）
2. 时间敏感点（sleep 是否足够、等待窗口是否覆盖机制延迟）
3. 环境依赖（端口、容器名、路径是否与讲义一致）
4. 数值依赖（是否依赖运行时长却未标注）
5. 预期输出是否给了判据（而非只有数字）
6. 失败时是否有补救办法
"""
import re
import sys

PATH = ("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/"
        "lessons/lesson-06-查询引擎与查询成本.md")

with open(PATH, encoding="utf-8") as f:
    text = f.read()

issues = []

m4 = text.find("第四幕")
m5 = text.find("第五幕")
act4 = text[m4:m5] if m4 > 0 and m5 > m4 else ""

# --- 0. 先建立"行号 → 是否在可执行 bash 块内"的映射 ---
# 后面的多项检查都依赖它，必须放在最前面
in_bash = {}
inside, lang = False, None
for i, ln in enumerate(text.splitlines(), 1):
    s = ln.strip()
    if s.startswith("```"):
        if not inside:
            inside, lang = True, s[3:].strip()
        else:
            inside, lang = False, None
        in_bash[i] = False
        continue
    in_bash[i] = inside and lang == "bash"

# --- 1. 省略性表述（只在可执行 bash 块内检查）---
for bad in ["（同上）", "(同上)", "列定义同上"]:
    for m in re.finditer(re.escape(bad), act4):
        ln = text[:m4 + m.start()].count("\n") + 1
        if in_bash.get(ln):
            issues.append(("P1", f"行{ln}: bash 命令含省略表述「{bad}」"))

# --- 2. 占位符（只在可执行 bash 块内检查）---
for ph in ["<", "YOUR_", "TODO"]:
    for m in re.finditer(re.escape(ph), act4):
        ln = text[:m4 + m.start()].count("\n") + 1
        if in_bash.get(ln):
            ctx = act4[max(0, m.start() - 60):m.start() + 60]
            # 排除 shell 重定向与比较运算符
            if ph == "<" and any(k in ctx for k in ["<(", "<<", "2<", " < ", "-lt"]):
                continue
            issues.append(("P2", f"行{ln}: bash 命令含疑似占位符「{ph}」"))

# --- 3. 时间敏感点：长 sleep 是否有说明 ---
sleeps = [(m.group(1), text[:m4 + m.start()].count("\n") + 1)
          for m in re.finditer(r"sleep (\d+)", act4)]
for n, ln in sleeps:
    if int(n) >= 30:
        idx = m4 + act4.find(f"sleep {n}")
        ctx = text[max(0, idx - 300):idx + 300]
        if not any(k in ctx for k in ["等待", "攒", "覆盖", "让"]):
            issues.append(("P1", f"行{ln}: sleep {n}s 未说明等待原因"))

# --- 4. recording rule 等待时间 ---
# 讲义说 interval=5s，等待 45 秒后校验产物
if "sleep 45" in act4 and "interval: 5s" not in text:
    issues.append(("P0", "recording rule 等待时间与 interval 不匹配"))

# --- 5. 端口与容器名一致性 ---
# 讲义声明：宿主 19094，容器 l6-prom / l6-app
if "19094" not in text:
    issues.append(("P1", "未声明宿主端口 19094"))
for name in ["l6-prom", "l6-app"]:
    if name not in text:
        issues.append(("P0", f"未出现容器名 {name}"))
# 课5 的端口不应出现在课6 的**可执行命令**里
# （说明性文字里做对比是合理的，不算问题）
for m in re.finditer(r"19090|19093", act4):
    ln = text[:m4 + m.start()].count("\n") + 1
    if in_bash.get(ln):
        issues.append(("P1", f"行{ln}: 第四幕 bash 命令里出现课5 端口 {m.group(0)}"))
    else:
        issues.append(("P2", f"行{ln}: 端口 {m.group(0)} 仅出现在说明文字中（确认是对比用途）"))

# --- 6. 关键校验步骤是否到位 ---
checks = [
    ("产物存在性校验", "产物" in act4 and "必须" in act4),
    ("点数同量级校验", "同量级" in act4 or "点数必须" in act4),
    ("噪声基线", "噪声" in act4),
]
for name, ok in checks:
    if not ok:
        issues.append(("P1", f"第四幕缺{name}"))

# --- 7. 预期输出与判据 ---
if act4.count("预期") < 5:
    issues.append(("P1", f"第四幕「预期」仅 {act4.count('预期')} 处，判据不足"))
if act4.count("判据") < 5:
    issues.append(("P1", f"第四幕「判据」仅 {act4.count('判据')} 处，判据不足"))

# --- 8. 失败补救 ---
if "如果" not in act4 or "⚠️" not in act4:
    issues.append(("P1", "第四幕缺少失败情况的补救说明"))

# --- 9. 数值依赖标注 ---
# 凡出现耗时对比，应说明会浮动
for kw in ["1.29 秒", "0.36 秒", "180000", "40854"]:
    if kw in text:
        idx = text.find(kw)
        ctx = text[max(0, idx - 400):idx + 400]
        if not any(k in ctx for k in ["浮动", "波动", "随环境", "别把", "看趋势"]):
            issues.append(("P1", f"数值 {kw} 未标注会随环境浮动"))

# --- 10. 坑 5（加号编码）是否在用到 .+ 的地方有提示 ---
# 只对**可执行 bash 块**内的 .+ 报警；promql 语法块与正文说明不算
for m in re.finditer(r"\{\s*__name__\s*=\s*~\s*[\"']\.\+[\"']", text):
    ln = text[:m.start()].count("\n") + 1
    if not in_bash.get(ln):
        continue                      # 非可执行命令 → 不报警
    ctx = text[max(0, m.start() - 600):m.start() + 600]
    if "%2B" not in ctx and "空格" not in ctx and "坑 5" not in ctx:
        issues.append(("P0", f"行{ln}: bash 命令里出现 .+ 但无加号编码警告（读者会命中 0 条）"))

# --- 11. 清理步骤 ---
if "清理" not in act4:
    issues.append(("P1", "第四幕缺清理步骤"))

print("=" * 60)
print("learner 视角评审")
print("=" * 60)
print(f"第四幕 sleep 出现次数: {len(sleeps)}")
print(f"最长 sleep: {max((int(n) for n, _ in sleeps), default=0)}s")
print()
if not issues:
    print("未发现 P0/P1/P2 问题")
else:
    for lvl, msg in issues:
        print(f"[{lvl}] {msg}")

p0 = sum(1 for l, _ in issues if l == "P0")
p1 = sum(1 for l, _ in issues if l == "P1")
p2 = sum(1 for l, _ in issues if l == "P2")
print()
print(f"合计: P0={p0}  P1={p1}  P2={p2}")
sys.exit(1 if p0 else 0)

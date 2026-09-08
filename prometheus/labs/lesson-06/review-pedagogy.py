"""课6 讲义评审 —— pedagogy 视角（教学法）。

检查维度：
1. 五幕结构完整性
2. 六要素展开（一句话定义/直觉建立/核心原理/示例演示/常见误区/一句话记住）
3. 结论是否有实测支撑（无实测须显式标注）
4. 第四幕命令是否"读者照抄能跑通"
5. 与前序课衔接、与后续课留白
6. 数值是否标注了浮动范围（禁止把单次测量当标准答案）
"""
import re
import sys

PATH = ("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/"
        "lessons/lesson-06-查询引擎与查询成本.md")

with open(PATH, encoding="utf-8") as f:
    text = f.read()

lines = text.splitlines()
issues = []

# --- 1. 五幕结构 ---
acts = ["第一幕", "第二幕", "第三幕", "第四幕", "第五幕"]
for a in acts:
    if a not in text:
        issues.append(("P0", f"缺{a}"))

# --- 2. 知识点与六要素 ---
kps = ["知识点 1", "知识点 2", "知识点 3"]
six = ["一句话定义", "直觉建立", "核心原理", "示例演示", "常见误区", "一句话记住"]
for kp in kps:
    if kp not in text:
        issues.append(("P0", f"缺{kp}"))
    # 按标题层级切分（### 知识点 N），避免正文里的交叉引用干扰定位
    heads = [(m.start(), m.group(0))
             for m in re.finditer(r"#{2,4}\s*知识点\s*\d", text)]
    for i, (pos, title) in enumerate(heads):
        end = heads[i + 1][0] if i + 1 < len(heads) else len(text)
        seg = text[pos:end]
        for e in six:
            if e not in seg:
                ln = text[:pos].count("\n") + 1
                issues.append(("P1", f"{title.strip()}（行{ln}）缺六要素之「{e}」"))

# --- 3. 实测支撑 ---
# 每条"实测"结论应有数据；无实测的断言应显式标注
for kw in ["未实测", "未展开", "标注为", "未在本课"]:
    pass
if "未实测" not in text and "未展开" not in text:
    issues.append(("P1", "通篇无「未实测/未展开」标注，需确认所有结论均有实测支撑"))

# --- 4. 第四幕命令可执行性 ---
m4 = text.find("第四幕")
m5 = text.find("第五幕")
act4 = text[m4:m5] if m4 > 0 and m5 > m4 else ""

# 4a. 禁止"（同上）""列定义同上"这类省略
for bad in ["（同上）", "(同上)", "同上）", "列定义同上", "略，同上"]:
    if bad in act4:
        issues.append(("P0", f"第四幕含省略表述「{bad}」，读者照抄无法执行"))

# 4b. 每条命令块应有预期输出或判据
blocks = re.findall(r"```bash\n(.*?)```", act4, re.S)
if len(blocks) < 10:
    issues.append(("P1", f"第四幕 bash 块仅 {len(blocks)} 个，偏少"))

# 4c. 关键：sleep 后是否有足够的等待说明
for m in re.finditer(r"sleep (\d+)", act4):
    n = int(m.group(1))
    if n >= 60:
        # 长 sleep 应附近有解释
        ctx = act4[max(0, m.start() - 200):m.end() + 200]
        if "等待" not in ctx and "攒" not in ctx and "覆盖" not in ctx:
            issues.append(("P2", f"长 sleep {n}s 附近缺少等待原因说明"))

# --- 5. 数值浮动标注 ---
# 凡出现"实测"的耗时数字，附近应有范围或波动说明
for m in re.finditer(r"(\d+\.?\d*)\s*ms", text):
    pass  # 逐个检查太噪音，改为抽查关键处

# 关键数值是否标注了浮动
for claim in ["1293.5", "194.4", "123.5", "126.2", "40854", "20832"]:
    if claim in text:
        idx = text.find(claim)
        ctx = text[max(0, idx - 500):idx + 500]
        if "浮动" not in ctx and "波动" not in ctx and "噪声" not in ctx \
           and "随" not in ctx and "看趋势" not in ctx and "别把" not in ctx:
            issues.append(("P2", f"数值 {claim} 附近未见浮动/波动说明"))

# --- 6. 衔接 ---
if "课 4" not in text or "课 5" not in text:
    issues.append(("P1", "未与前序课（课4/课5）衔接"))
if "课 7" not in text and "阶段 3" not in text:
    issues.append(("P1", "未与后续课衔接"))
if "接力提示词" not in text:
    issues.append(("P1", "缺接力提示词"))
if "课程导航" not in text:
    issues.append(("P1", "缺课程导航"))
if "速览" not in text:
    issues.append(("P1", "缺速览"))
if "小测" not in text:
    issues.append(("P1", "缺小测"))

# --- 7. 命令避坑 ---
if "命令避坑" not in act4:
    issues.append(("P1", "第四幕缺「命令避坑」块"))

# --- 8. 评审结论块占位 ---
if "本课评审结论" not in text:
    issues.append(("P1", "缺「本课评审结论」块（课5 范式要求对用户可见）"))

print("=" * 60)
print("pedagogy 视角评审")
print("=" * 60)
print(f"讲义行数: {len(lines)}")
print(f"bash 块数: {len(blocks)}")
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

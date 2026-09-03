#!/usr/bin/env python3
# 课 12 评审 Agent A：教学法视角（pedagogy）
import re, sys

P = "/mnt/d/projects/learning/victoriametrics/stages/5-生产落地/12-备份恢复迁移与选型决策.md"
try:
    src = open(P, encoding="utf-8").read()
except Exception as e:
    print("READ FAIL:", e); sys.exit(1)

lines = src.split("\n")
print("=" * 70)
print("课 12 评审 · Agent A（教学法视角 / pedagogy）")
print(f"文件：{P}")
print(f"总行数：{len(lines)}  总字符：{len(src)}")
print("=" * 70)

issues = []

# 1. 五幕结构
acts = ["第一幕", "第二幕", "第三幕", "第四幕", "第五幕"]
found = {a: any(a in l and l.startswith("#") for l in lines) for a in acts}
print("\n[1] 五幕结构")
for a in acts:
    print(f"   {a}: {'✅' if found[a] else '❌ 缺失'}")
    if not found[a]:
        issues.append(("P0", f"{a} 缺失"))

# 2. 三个知识点的六要素
kp_titles = ["知识点 1：快照与备份恢复", "知识点 2：迁移路径", "知识点 3：选型决策"]
six = ["一句话定义", "直觉建立", "核心原理", "示例演示", "常见误区", "一句话记住"]
print("\n[2] 知识点六要素")
kp_pos = []
for t in kp_titles:
    idx = [i for i, l in enumerate(lines) if l.startswith("### ") and t in l]
    kp_pos.append(idx[0] if idx else -1)
    print(f"   {t}: {'✅ 存在' if idx else '❌ 缺失'}")
    if not idx:
        issues.append(("P0", f"{t} 缺失"))

for n, (t, pos) in enumerate(zip(kp_titles, kp_pos), 1):
    if pos < 0:
        continue
    end = kp_pos[n] if n < len(kp_pos) else len(lines)
    end = end if end > pos else len(lines)
    seg = "\n".join(lines[pos:end])
    print(f"\n   --- 知识点 {n} 六要素核查 ---")
    for s in six:
        ok = s in seg
        print(f"      {s}: {'✅' if ok else '❌ 缺失'}")
        if not ok:
            issues.append(("P1", f"知识点 {n} 缺少六要素之「{s}」"))

# 3. 生活化类比 + 类比失效边界
print("\n[3] 生活化类比与失效边界")
analog = src.count("💡 **类比**")
boundary = src.count("类比失效的边界")
print(f"   类比数量：{analog}")
print(f"   「类比失效的边界」数量：{boundary}")
if analog == 0:
    issues.append(("P1", "无生活化类比"))
if boundary < analog:
    issues.append(("P1", f"有 {analog} 处类比但只有 {boundary} 处失效边界说明"))

# 4. Mermaid 图
print("\n[4] Mermaid 图表")
mer = src.count("```mermaid")
print(f"   Mermaid 代码块：{mer} 个")
print("   ⚠️ 本课流程图较少，若关键机制缺少图示应补充")

# 5. 强制结尾段落
print("\n[5] 强制结尾段落")
for k in ["🚀 下一批接力提示词", "🧭 课程导航"]:
    ok = k in src
    print(f"   {k}: {'✅' if ok else '❌ 缺失'}")
    if not ok:
        issues.append(("P0", f"缺少 {k}"))

# 6. 常见误区汇总数量
print("\n[6] 常见误区")
m = re.findall(r"误区 (\d+)：", src)
print(f"   编号误区数量：{len(m)}")
mm = re.search(r"常见误区汇总\n\n(.*?)\n\n### 决策清单", src, re.S)
if mm:
    cnt = len([l for l in mm.group(1).split("\n") if l.strip() and l.strip()[0].isdigit()])
    print(f"   汇总清单条目：{cnt}")
    if cnt < 5:
        issues.append(("P2", "误区汇总条目偏少"))

# 7. 绝对化表述检测（误报高发区，需人工核验）
print("\n[7] 绝对化表述检测（需人工核验是否为误报）")
abs_words = ["绝不", "绝对不会", "永远不", "完全不会", "100% 保证", "任何情况下都"]
for w in abs_words:
    c = src.count(w)
    if c:
        for i, l in enumerate(lines, 1):
            if w in l:
                print(f"   L{i}: 「{w}」→ {l.strip()[:90]}")
        issues.append(("P2", f"绝对化表述「{w}」出现 {c} 次，需核验是否有实测支撑"))

# 8. 危险操作安全提示
print("\n[8] 危险操作安全提示")
danger = ["rm -rf", "docker rm -f", "docker volume rm", "delete_series"]
for d in danger:
    c = src.count(d)
    print(f"   「{d}」出现 {c} 次")
has_warn = "⚠️" in src or "安全提示" in src
print(f"   含安全提示标记：{'✅' if has_warn else '❌'}")
if not has_warn:
    issues.append(("P1", "涉及危险操作但无安全提示"))

# 9. 数据支撑检查
print("\n[9] 实测数据密度")
nums = len(re.findall(r"\d[\d,]{2,}", src))
print(f"   三位以上数字出现：{nums} 处")
if nums < 40:
    issues.append(("P2", "实测数据密度偏低"))

# 10. 诚实性检查（是否有模糊表述）
print("\n[10] 诚实性检查（模糊表述）")
vague = ["大幅提升", "显著提高", "非常快", "极其高效", "快很多倍"]
for v in vague:
    if v in src:
        issues.append(("P2", f"模糊表述「{v}」应替换为实测数字"))
        print(f"   ⚠️ 「{v}」")

print("\n" + "=" * 70)
print("问题汇总")
print("=" * 70)
if not issues:
    print("   无问题")
else:
    for lv, d in issues:
        print(f"   [{lv}] {d}")
p0 = [i for i in issues if i[0] == "P0"]
p1 = [i for i in issues if i[0] == "P1"]
p2 = [i for i in issues if i[0] == "P2"]
print(f"\n   P0={len(p0)}  P1={len(p1)}  P2={len(p2)}")

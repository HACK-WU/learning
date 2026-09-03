#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 11 评审 · Agent A：pedagogy（教学法视角）"""
import re, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

P = r"/mnt/d/projects/learning/victoriametrics/stages/5-生产落地/11-vmagent与vmalert.md"
txt = open(P, encoding='utf-8').read()
lines = txt.split('\n')

print("=" * 70)
print("Agent A · pedagogy 视角评审（教学法 / 结构 / 认知逻辑）")
print("=" * 70)

# A 组：结构合规
print("\n【A 组 · 结构合规】\n")

checks = [
    ("五幕结构-场景引入", "## 第一幕 · 场景引入" in txt),
    ("五幕结构-认知冲突", "## 第二幕 · 认知冲突" in txt),
    ("五幕结构-层层揭示", "## 第三幕 · 层层揭示" in txt),
    ("五幕结构-实操验证", "## 第四幕 · 实操验证" in txt),
    ("五幕结构-体系收束", "## 第五幕 · 体系收束" in txt),
    ("接力提示词段", "🚀 下一批接力提示词" in txt),
    ("课程导航段", "🧭 课程导航" in txt),
    ("上一课链接", "上一课：[课 10" in txt or "**上一课**" in txt),
    ("返回课程目录", "02-课程目录.md" in txt),
]

for name, ok in checks:
    print(f"  [{'OK ' if ok else 'MISS'}] {name}")

# 六要素：每个知识点
print("\n【六要素核查 · 逐知识点】\n")
# 按知识点切分
parts = re.split(r'\n### 知识点 ', txt)
for p in parts[1:]:
    kname = p.split('\n')[0][:40]
    six = {
        "一句话定义": "#### 一句话定义" in p,
        "直觉建立": "#### 直觉建立" in p,
        "核心原理": "#### 核心原理" in p,
        "示例演示": "#### 示例演示" in p or "示例演示 1" in p,
        "常见误区": "#### 常见误区" in p,
        "一句话记住": "#### 一句话记住" in p,
    }
    miss = [k for k, v in six.items() if not v]
    status = "OK" if not miss else "缺: " + ",".join(miss)
    print(f"  知识点 {kname}")
    print(f"      {status}")

# 类比及其失效边界
print("\n【类比与失效边界】\n")
analogies = re.findall(r'>\s*💡\s*\*\*类比\*\*', txt)
boundaries = re.findall(r'\*\*类比失效的边界\*\*', txt)
print(f"  生活化类比数量: {len(analogies)}")
print(f"  失效边界声明:   {len(boundaries)}")
if analogies and not boundaries:
    print("  [P1] 有类比但未指出失效边界")

# 图表合规
print("\n【图表合规】\n")
mermaid = len(re.findall(r'```mermaid', txt))
svg = len(re.findall(r'\.svg', txt))
print(f"  Mermaid 图: {mermaid} 个")
print(f"  SVG 引用:   {svg} 个")
print(f"  [{'OK ' if mermaid > 0 else 'MISS'}] 至少一张 Mermaid 图")

# B 组：数据事实
print("\n【B 组 · 数据事实】\n")
print(f"  总行数: {len(lines)}")
print(f"  总字符: {len(txt)}")

# 数字自洽性：检查关键数字是否前后一致
key_nums = {
    "150": txt.count("150"),
    "722357": txt.count("722357"),
    "1,238,996": txt.count("1,238,996"),
    "1.151.0": txt.count("1.151.0"),
}
print("\n  关键数字出现次数（自洽性抽查）:")
for k, v in key_nums.items():
    print(f"      {k}: {v} 次")

# 检查是否有未验证的绝对化表述
print("\n【绝对化表述扫描】\n")
absolute = [
    (r'快\s*\d+\s*倍', "性能倍数宣称"),
    (r'提升\s*\d+\s*倍', "性能倍数宣称"),
    (r'一定[会不会]', "绝对化"),
    (r'绝不', "绝对化"),
]
found_any = False
for pat, label in absolute:
    ms = re.findall(pat, txt)
    if ms:
        found_any = True
        print(f"  [注意] {label}: {ms[:5]}")
if not found_any:
    print("  未发现无依据的绝对化表述")

# 诚实性检查
print("\n【诚实性 / 未闭环标注】\n")
honest = [
    ("⚠️", "警告标记"),
    ("诚实说明", "诚实说明"),
    ("未闭环", "未闭环标注"),
]
for mark, label in honest:
    c = txt.count(mark)
    print(f"  {label} ({mark}): {c} 处")

print("\n" + "=" * 70)
print("Agent A 评审结束")
print("=" * 70)

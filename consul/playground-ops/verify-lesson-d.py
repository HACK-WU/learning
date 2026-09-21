#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""方案 A 交付校验：链接存在性 + 内容断言
先自检：用已知正确/已知错误的样本验证脚本鉴别力，再跑真实验证
"""
import os, re, sys

ROOT = '/mnt/d/projects/learning/consul'
FAILS, PASSES = [], []

def P(name): PASSES.append(name)
def F(name, detail): FAILS.append((name, detail))

def read(p):
    try:
        with open(p, encoding='utf-8') as f: return f.read()
    except Exception as e:
        return None

def check_links(md_path):
    """检查 md 文件内所有相对链接是否存在"""
    base = os.path.dirname(md_path)
    txt = read(md_path) or ''
    broken, total = [], 0
    for m in re.finditer(r'\[([^\]]*)\]\(([^)]+)\)', txt):
        url = m.group(2).strip()
        if url.startswith(('http://', 'https://', '#', 'mailto:')): continue
        url = url.split('#')[0]
        if not url: continue
        total += 1
        target = os.path.normpath(os.path.join(base, url))
        if not os.path.exists(target):
            broken.append((url, target))
    return total, broken

def assert_in(md_path, needle, label):
    txt = read(md_path) or ''
    if needle in txt: P(label)
    else: F(label, f"未找到: {needle!r} in {os.path.basename(md_path)}")

def assert_not_in(md_path, needle, label):
    txt = read(md_path) or ''
    if needle not in txt: P(label)
    else: F(label, f"不应存在: {needle!r}")

# ============ 0. 自检：验证脚本自身鉴别力 ============
print("=" * 60)
print("0. 脚本自检（先验证鉴别力，避免误报/漏报）")
print("=" * 60)
# 已知正确的文件
t, b = check_links(os.path.join(ROOT, '应用实战/INDEX.md'))
print(f"  已知存在的文件索引：{t} 条链接，{len(b)} 条断链")
# 人为构造一个必然断链的探测
probe = os.path.join(ROOT, '__probe__.md')
with open(probe, 'w', encoding='utf-8') as f:
    f.write('[good](./应用实战/INDEX.md)\n[bad](./不存在的文件-xyz.md)\n')
t2, b2 = check_links(probe)
os.remove(probe)
if len(b2) == 1 and t2 == 2:
    P("脚本自检：能识别断链且不误报好链")
    print(f"  自检通过：2 条链接中准确识别 1 条断链")
else:
    F("脚本自检", f"自检异常：total={t2} broken={len(b2)}，脚本不可信")
    print(f"  ❌ 自检失败，脚本不可信，终止"); sys.exit(1)

# ============ 1. 新增/修改文件的链接校验 ============
print()
print("=" * 60)
print("1. 本轮新增/修改文件的链接校验")
print("=" * 60)
targets = [
    'practices/实战D-灰度发布与流量切分/README.md',
    '应用实战/INDEX.md',
    'stages/2-核心能力拆解/lessons/lesson-07-多数据中心与服务网格.md',
    'stages/3-横向对比/lessons/lesson-09-四大竞品逐个看.md',
    'final-课程手册.md',
    '00-评审清单.md',
    '应用实战篇-逐课判定.md',
]
total_all = 0
for rel in targets:
    p = os.path.join(ROOT, rel)
    t, b = check_links(p)
    total_all += t
    if b:
        for url, tgt in b:
            F(f"断链 {os.path.basename(rel)}", f"{url} -> {tgt}")
        print(f"  ❌ {rel}: {t} 条，{len(b)} 断链")
    else:
        P(f"链接OK {os.path.basename(rel)}")
        print(f"  ✅ {rel}: {t} 条链接全部可达")
print(f"  合计校验 {total_all} 条链接")

# ============ 2. SVG 图片引用校验 ============
print()
print("=" * 60)
print("2. D 篇 SVG 引用与 XML 合法性")
print("=" * 60)
d_path = os.path.join(ROOT, 'practices/实战D-灰度发布与流量切分/README.md')
d_txt = read(d_path)
import xml.etree.ElementTree as ET
svg_refs = re.findall(r'!\[[^\]]*\]\((\.?\.?/assets/[^)]+\.svg)\)', d_txt)
print(f"  D 篇引用 SVG: {len(svg_refs)} 张")
if len(svg_refs) == 3:
    P("D 篇 SVG 引用数为 3")
else:
    F("D 篇 SVG 引用数", f"期望 3，实际 {len(svg_refs)}")
for ref in svg_refs:
    sp = os.path.join(ROOT, 'practices/实战D-灰度发布与流量切分', ref)
    if not os.path.exists(sp):
        F("SVG 缺失", sp); continue
    try:
        ET.parse(sp); P(f"SVG XML 合法 {os.path.basename(sp)}")
    except Exception as e:
        F("SVG XML 非法", f"{sp}: {e}")

# ============ 3. 内容断言 ============
print()
print("=" * 60)
print("3. 内容断言")
print("=" * 60)
l7 = os.path.join(ROOT, 'stages/2-核心能力拆解/lessons/lesson-07-多数据中心与服务网格.md')
l9 = os.path.join(ROOT, 'stages/3-横向对比/lessons/lesson-09-四大竞品逐个看.md')
idx = os.path.join(ROOT, '应用实战/INDEX.md')

# 课 7：新增章节存在
assert_in(l7, '插播：同一个"流量"问题的另一半', '课7 新增灰度章节')
assert_in(l7, 'discovery chain', '课7 含 discovery chain')
assert_in(l7, '权重和必须 = 100', '课7 含权重约束')
assert_in(l7, 'does not permit advanced routing', '课7 含 tcp 报错原文')
assert_in(l7, '网关配置写入成功 ≠ 网关在运行', '课7 含网关边界')
assert_in(l7, '实战D-灰度发布与流量切分', '课7 导航含 D 篇')
assert_in(l7, 'None', '课7 含权重0返回None')

# 课 9：错误结论已修正
assert_in(l9, '灰度发布**（服务流量维度）', '课9 已拆分灰度维度')
assert_in(l9, 'ServiceSplitter', '课9 已承认有 ServiceSplitter')

# 索引：D 篇已登记
assert_in(idx, '实战D-灰度发布与流量切分', 'INDEX 含 D 篇')
assert_in(idx, '四篇各自', 'INDEX 篇数已更新为四')
assert_in(idx, 'D 篇的特殊边界', 'INDEX 含 D 篇边界说明')

# D 篇：结构与硬结论
assert_in(d_path, '## 场景 1', 'D篇 有场景')
assert_in(d_path, '### ① 基础实现', 'D篇 有基础实现')
assert_in(d_path, '### ② 综合实现', 'D篇 有综合实现')
assert_in(d_path, '### ③ 边界', 'D篇 有边界段')
assert_in(d_path, '🎯 会用标志', 'D篇 有会用标志')
assert_in(d_path, '📎 实测证据', 'D篇 有实测证据')
assert_in(d_path, '仍存在的已知边界', 'D篇 有已知边界')
assert_in(d_path, 'the sum of all split weights must be 100', 'D篇 含权重报错原文')
assert_in(d_path, '未监听', 'D篇 含网关未监听结论')

# ============ 4. 手册口径统一（第二轮） ============
print()
print("=" * 60)
print("4. final-课程手册 口径统一")
print("=" * 60)
man = os.path.join(ROOT, 'final-课程手册.md')
idx2 = os.path.join(ROOT, '应用实战/INDEX.md')
cat = os.path.join(ROOT, '02-课程目录.md')
arch = os.path.join(ROOT, '00-学习档案.md')
judge = os.path.join(ROOT, '应用实战篇-逐课判定.md')

assert_in(man, '应用实战 4 篇', '手册头部 4 篇')
assert_in(man, '## 五、应用实战四篇', '手册第五节标题')
assert_in(man, '实战D-灰度发布与流量切分', '手册含 D 篇条目')
assert_in(man, '实战 D 篇为纯控制面实测', '手册含 D 篇边界')
assert_not_in(man, '应用实战 3 篇', '手册无残留3篇(头)')
assert_in(cat, '实战四篇', '课程目录 四篇')
assert_in(arch, '实战四篇', '学习档案 四篇')
assert_in(judge, '四篇均遵守课程铁律', '逐课判定 四篇')
assert_in(idx2, '配套 4 篇', 'INDEX 配套4篇')
assert_not_in(idx2, '配套 3 篇', 'INDEX 无残留3篇')

# ============ 汇总 ============
print()
print("=" * 60)
print(f"汇总：{len(PASSES)} PASS / {len(FAILS)} FAIL")
print("=" * 60)
if FAILS:
    for n, d in FAILS:
        print(f"  ❌ {n}: {d}")
    sys.exit(1)
else:
    print("  ✅ 全部通过")

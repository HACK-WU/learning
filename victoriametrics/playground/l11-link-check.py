#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 11 交付后：全仓链接可达性检查"""
import io, sys, os, re, glob
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

BASE = r"/mnt/d/projects/learning/victoriametrics"

def check_file(path):
    """检查单个 md 文件里的相对链接"""
    if not os.path.exists(path):
        return []
    txt = open(path, encoding='utf-8').read()
    # 排除代码块里的链接
    txt_nb = re.sub(r'```.*?```', '', txt, flags=re.S)
    links = re.findall(r'\]\((\.\.?/[^)#]+)', txt_nb)
    bad = []
    for l in set(links):
        target = os.path.normpath(os.path.join(os.path.dirname(path), l))
        if not os.path.exists(target):
            bad.append(l)
    return bad

print("=" * 70)
print("链接可达性检查")
print("=" * 70)

md_files = []
for root, dirs, fs in os.walk(BASE):
    dirs[:] = [d for d in dirs if d not in ('playground', '.git', 'assets', 'cluster-data', 'data')]
    for f in fs:
        if f.endswith('.md'):
            md_files.append(os.path.join(root, f))

total_bad = 0
for f in sorted(md_files):
    bad = check_file(f)
    rel = os.path.relpath(f, BASE)
    if bad:
        total_bad += len(bad)
        print(f"\n  [FAIL] {rel}")
        for b in bad:
            print(f"         -> {b}")
    else:
        print(f"  [OK  ] {rel}")

print("\n" + "=" * 70)
print(f"检查文件数: {len(md_files)}   失效链接: {total_bad}")
print("=" * 70)

# 专项：课 11 讲义的链接
print("\n【课 11 讲义链接专项】\n")
l11 = os.path.join(BASE, "stages/5-生产落地/11-vmagent与vmalert.md")
bad = check_file(l11)
if bad:
    for b in bad:
        print(f"  [FAIL] {b}")
else:
    print("  课 11 讲义全部链接可达 ✅")

# 专项：两个索引 + 各阶段 README
print("\n【索引与阶段 README 返回链接层级校验】\n")
key_files = [
    "02-课程目录.md",
    "01-学习路径总览.md",
    "stages/5-生产落地/README.md",
]
for kf in key_files:
    p = os.path.join(BASE, kf)
    bad = check_file(p)
    print(f"  {'[FAIL]' if bad else '[OK  ]'} {kf}" + (f"  失效: {bad}" if bad else ""))

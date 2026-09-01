#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 9 交付前自检：校验讲义引用的脚本与链接是否真实存在。"""
import os
import re

BASE = os.path.dirname(os.path.abspath(__file__))
LESSON = os.path.join(
    BASE, '..', 'stages', '4-进阶与工程落地', 'lessons',
    'lesson-09-Python客户端工程实践.md')
PLAYGROUND = BASE

print("=" * 70)
print("课 9 交付前自检")
print("=" * 70)

with open(LESSON, encoding='utf-8') as f:
    text = f.read()

# 1. 检查讲义中引用的 l9-*.py 是否都存在
refs = sorted(set(re.findall(r'l9-[a-z0-9\-]+\.py', text)))
print("\n【1】讲义引用的 l9 脚本（%d 个）" % len(refs))
all_ok = True
for r in refs:
    p = os.path.join(PLAYGROUND, r)
    ok = os.path.isfile(p)
    all_ok = all_ok and ok
    print("  %-28s %s" % (r, "OK" if ok else "MISSING"))

# 2. 检查内部 Markdown 链接
print("\n【2】讲义内的相对链接")
lesson_dir = os.path.dirname(LESSON)
links = re.findall(r'\]\((\./[^)]+|\.\./[^)]+)\)', text)
for lk in sorted(set(links)):
    p = os.path.normpath(os.path.join(lesson_dir, lk))
    ok = os.path.exists(p)
    all_ok = all_ok and ok
    print("  %-45s %s" % (lk, "OK" if ok else "MISSING"))

# 3. 统计
print("\n【3】讲义规模")
lines = text.count('\n') + 1
print("  行数：%d" % lines)
print("  字符数：%d" % len(text))

# 4. 检查是否残留占位符
print("\n【4】占位符检查")
for pat, desc in [('待 Phase', 'Phase 占位'), ('TODO', 'TODO'),
                  ('待补充', '待补充')]:
    n = text.count(pat)
    print("  %-12s %d 处" % (desc, n))
    if pat == '待 Phase' and n > 0:
        all_ok = False

print("\n" + "=" * 70)
print("自检结果：%s" % ("全部通过" if all_ok else "存在问题，请检查"))
print("=" * 70)

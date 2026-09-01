#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 交付前自检：校验讲义引用的脚本、链接与占位符。"""
import os
import re

BASE = os.path.dirname(os.path.abspath(__file__))
LESSON = os.path.join(
    BASE, '..', 'stages', '4-进阶与工程落地', 'lessons',
    'lesson-10-高级特性.md')

print("=" * 70)
print("课 10 交付前自检")
print("=" * 70)

with open(LESSON, encoding='utf-8') as f:
    text = f.read()

ok = True

# 1. 引用的脚本
refs = sorted(set(re.findall(r'l10-[a-z0-9\-]+\.py', text)))
print("\n【1】讲义引用的 l10 脚本（%d 个）" % len(refs))
for r in refs:
    p = os.path.join(BASE, r)
    good = os.path.isfile(p)
    ok = ok and good
    print("  %-32s %s" % (r, "OK" if good else "MISSING"))

# 2. 相对链接
print("\n【2】讲义内的相对链接")
lesson_dir = os.path.dirname(LESSON)
links = sorted(set(re.findall(r'\]\((\./[^)]+)\)', text)))
for lk in links:
    p = os.path.normpath(os.path.join(lesson_dir, lk))
    good = os.path.exists(p)
    ok = ok and good
    print("  %-40s %s" % (lk, "OK" if good else "MISSING"))

# 3. 规模
print("\n【3】讲义规模")
print("  行数：%d" % (text.count('\n') + 1))
print("  字符数：%d" % len(text))

# 4. 占位符 / 错别字
print("\n【4】占位符与错别字检查")
for pat, desc in [('待 Phase', 'Phase 占位'), ('TODO', 'TODO'),
                  ('待补充', '待补充'), ('работа', '俄文残留'),
                  ('TODO_PLACEHOLDER', '占位符')]:
    n = text.count(pat)
    print("  %-12s %d 处" % (desc, n))
    if n > 0 and pat in ('待 Phase', 'работа'):
        ok = False

# 5. 小测答案闭合
print("\n【5】小测结构")
n_q = len(re.findall(r'### Q\d+', text))
n_details = text.count('<details>')
n_summary = text.count('</details>')
print("  题目数：%d" % n_q)
print("  <details>：%d  </details>：%d" % (n_details, n_summary))
if n_details != n_summary:
    print("  ⚠️ details 标签不配对")
    ok = False

print("\n" + "=" * 70)
print("自检结果：%s" % ("全部通过" if ok else "存在问题，请检查"))
print("=" * 70)

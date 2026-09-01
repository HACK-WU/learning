#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 11 交付前自检：校验脚本引用、链接、占位符、小测结构与环境残留。"""
import os
import re
import subprocess

BASE = os.path.dirname(os.path.abspath(__file__))
LESSON = os.path.join(
    BASE, '..', 'stages', '4-进阶与工程落地', 'lessons',
    'lesson-11-集群与高可用.md')

print("=" * 70)
print("课 11 交付前自检")
print("=" * 70)

with open(LESSON, encoding='utf-8') as f:
    text = f.read()

ok = True

# 1. 引用的脚本
refs = sorted(set(re.findall(r'l11-[a-z0-9\-]+\.(?:py|sh)', text)))
print("\n【1】讲义引用的 l11 脚本（%d 个）" % len(refs))
for r in refs:
    p = os.path.join(BASE, r)
    good = os.path.isfile(p)
    ok = ok and good
    print("  %-32s %s" % (r, "OK" if good else "MISSING"))

# 2. 相对链接
print("\n【2】讲义内的相对链接")
lesson_dir = os.path.dirname(LESSON)
for lk in sorted(set(re.findall(r'\]\((\./[^)]+)\)', text))):
    p = os.path.normpath(os.path.join(lesson_dir, lk))
    good = os.path.exists(p)
    ok = ok and good
    print("  %-40s %s" % (lk, "OK" if good else "MISSING"))

# 3. 规模
print("\n【3】讲义规模")
print("  行数：%d" % (text.count('\n') + 1))
print("  字符数：%d" % len(text))

# 4. 占位符
print("\n【4】占位符检查")
for pat, desc in [('待 Phase', 'Phase 占位'), ('待补充', '待补充'),
                  ('TODO_PLACEHOLDER', '占位符'), ('⏳', '沙漏占位')]:
    n = text.count(pat)
    print("  %-14s %d 处" % (desc, n))
    if n > 0:
        ok = False

# 5. 小测结构
print("\n【5】小测结构")
n_q = len(re.findall(r'### Q\d+', text))
n_open = text.count('<details>')
n_close = text.count('</details>')
print("  题目数：%d" % n_q)
print("  <details>：%d  </details>：%d" % (n_open, n_close))
if n_open != n_close:
    print("  ⚠️ details 标签不配对")
    ok = False

# 6. 集群环境残留
print("\n【6】集群环境残留")
r = subprocess.run(
    ['docker', 'ps', '-a', '--format', '{{.Names}}'],
    capture_output=True, text=True, timeout=60)
names = (r.stdout or '').split()
for n in ('rmq1', 'rmq2', 'rmq3'):
    print("  %-8s %s" % (n, "在（本课集群）" if n in names else "无"))
if 'rmq-upstream' in names:
    print("  ⚠️ rmq-upstream 残留（应已清理）")
    ok = False
else:
    print("  rmq-upstream 无残留 ✅")

# 7. 既有环境完好
print("\n【7】既有环境 rabbitmq-learn")
r = subprocess.run(
    ['docker', 'ps', '--filter', 'name=rabbitmq-learn',
     '--format', '{{.Names}}\t{{.Status}}'],
    capture_output=True, text=True, timeout=60)
print("  %s" % (r.stdout or '未找到').strip())

# 8. 集群内残留队列
print("\n【8】集群内 l11 残留队列")
r = subprocess.run(
    ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues', 'name'],
    capture_output=True, text=True, timeout=90)
lines = [l.strip() for l in (r.stdout or '').splitlines()[2:] if l.strip()]
stray = [l for l in lines if 'l11' in l]
print("  队列总数：%d" % len(lines))
print("  l11 残留：%s" % (stray if stray else "无 ✅"))
if stray:
    ok = False

# 9. 集群内残留 policy / parameter
print("\n【9】集群内残留 policy / parameter")
r = subprocess.run(
    ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_policies'],
    capture_output=True, text=True, timeout=90)
pol = [l for l in (r.stdout or '').splitlines() if 'l11' in l]
r2 = subprocess.run(
    ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_parameters'],
    capture_output=True, text=True, timeout=90)
par = [l for l in (r2.stdout or '').splitlines() if 'l11' in l]
print("  l11 policy    ：%s" % (pol if pol else "无 ✅"))
print("  l11 parameter ：%s" % (par if par else "无 ✅"))

print("\n" + "=" * 70)
print("自检结果：%s" % ("全部通过" if ok else "存在问题，请检查"))
print("=" * 70)

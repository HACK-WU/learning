#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全目录相对链接回归校验（含脚本自检）"""
import os, re, sys

ROOT = '/mnt/d/projects/learning/consul'
SKIP_DIRS = {'playground-ops', '.git', 'web-index', 'node_modules'}

def iter_md():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            if fn.endswith('.md'):
                yield os.path.join(dp, fn)

def check(md):
    base = os.path.dirname(md)
    try:
        txt = open(md, encoding='utf-8').read()
    except Exception:
        return 0, []
    broken = []
    total = 0
    for m in re.finditer(r'\[([^\]]*)\]\(([^)]+)\)', txt):
        url = m.group(2).strip()
        if url.startswith(('http://', 'https://', '#', 'mailto:')):
            continue
        url = url.split('#')[0]
        if not url:
            continue
        total += 1
        if not os.path.exists(os.path.normpath(os.path.join(base, url))):
            broken.append((url, os.path.normpath(os.path.join(base, url))))
    return total, broken

# 自检
probe = os.path.join(ROOT, '__probe_all__.md')
open(probe, 'w', encoding='utf-8').write(
    '[good](./00-学习档案.md)\n[bad](./绝对不存在-xyz.md)\n')
t, b = check(probe)
os.remove(probe)
print("=" * 60)
print("0. 脚本自检")
print("=" * 60)
if t == 2 and len(b) == 1:
    print(f"  ✅ 自检通过（2 条链接准确识别 1 条断链）")
else:
    print(f"  ❌ 自检失败 total={t} broken={len(b)}，脚本不可信"); sys.exit(1)

print()
print("=" * 60)
print("1. 全目录 md 相对链接校验")
print("=" * 60)
total_all = 0
bad_files = 0
md_count = 0
for md in iter_md():
    md_count += 1
    t, b = check(md)
    total_all += t
    if b:
        bad_files += 1
        for url, tgt in b:
            print(f"  ❌ {os.path.relpath(md, ROOT)}")
            print(f"       {url} -> {tgt}")

print()
print("=" * 60)
print(f"汇总：扫描 {md_count} 个 md 文件 / {total_all} 条相对链接 / {bad_files} 个文件含断链")
print("=" * 60)
if bad_files:
    print("  ❌ 存在断链")
    sys.exit(1)
print("  ✅ 0 断链")

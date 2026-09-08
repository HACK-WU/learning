#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""最终复检：根目录 md 全量链接检查 + 档案回写确认 + 临时文件盘点。"""
import pathlib
import re
import subprocess

BASE = pathlib.Path("/mnt/d/projects/learning/prometheus")
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

print("=" * 70)
print("最终复检")
print("=" * 70)

# 1. 根目录 md 全量链接
print("\n[1] 根目录 md 链接全量检查")
total = bad = 0
for p in sorted(BASE.glob("*.md")):
    text = p.read_text(encoding="utf-8")
    miss = []
    for label, target in LINK.findall(text):
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        t = target.split("#")[0]
        if not t:
            continue
        if not (p.parent / t).resolve().exists():
            miss.append((label, target))
    total += len(LINK.findall(text))
    bad += len(miss)
    flag = "✅" if not miss else f"❌ {len(miss)}"
    print(f"    {p.name:<28} {flag}")
    for label, target in miss:
        print(f"        → [{label}] {target}")
print(f"    合计 {total} 条链接，断链 {bad}")

# 2. 档案回写确认
print("\n[2] 四处档案回写确认")
checks = [
    ("02-课程目录.md", ["final-课程手册.md（✅"]),
    ("01-学习路径总览.md", ["Phase 4 课程手册汇总已于 2026-09-08 完成"]),
    ("00-评审清单.md", ["**课程手册汇总**（Phase 4）"]),
    ("00-学习档案.md", ["## Phase 4 课程手册汇总（2026-09-08）"]),
]
for name, keys in checks:
    p = BASE / name
    t = p.read_text(encoding="utf-8")
    for k in keys:
        print(f"    {'✅' if k in t else '❌'} {name}: {k[:40]}")

# 3. 产物清单
print("\n[3] 根目录产物")
for p in sorted(BASE.glob("*.md")):
    print(f"    {p.stat().st_size:>7}  {p.name}")

# 4. 临时脚本盘点（本轮在 labs/phase5 下生成的）
print("\n[4] labs/phase5 下的脚本（本轮生成）")
d = BASE / "labs" / "phase5"
if d.exists():
    for p in sorted(d.glob("*")):
        print(f"    {p.stat().st_size:>7}  {p.name}")

# 5. git 卫生检查
print("\n[5] git 状态（prometheus/ 下）")
r = subprocess.run(
    "git status --porcelain -- prometheus/ | head -20",
    shell=True, capture_output=True, text=True, cwd=str(BASE.parent))
print(r.stdout.rstrip()[:900] or "    (空)")

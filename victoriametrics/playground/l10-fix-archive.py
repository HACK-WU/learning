# -*- coding: utf-8 -*-
"""
课 10 收尾修复：
  1. 修正学习档案课 10 三行的勾选（之前列索引算错，实际状态列在 [4]）
  2. 阶段 4 概览 status: 进行中 -> 已完成
"""
import io
import os

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"

print("=" * 60)
print(" 1. 修正 00-学习档案.md 课 10 三行")
print("=" * 60)
p = os.path.join(ROOT, "00-学习档案.md")
lines = io.open(p, encoding="utf-8").read().split("\n")
fixed = 0
for i, ln in enumerate(lines):
    if not ln.strip().startswith("|"):
        continue
    parts = ln.split("|")
    # 只处理 课 10 的进度表行：段数 8，[2]=='课 10'，[4] 是状态
    if len(parts) != 8:
        continue
    if parts[2].strip() != "课 10":
        continue
    st = parts[4].strip()
    if "未开始" in st or "⬜" in st:
        parts[4] = " ✅ 已完成"
        fixed += 1
    if parts[5].strip() in ("", "-"):
        parts[5] = " " + DATE
    if parts[6].strip() in ("", "-"):
        parts[6] = " 见讲义"
    lines[i] = "|".join(parts)
io.open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("  勾选 %d 行" % fixed)
print("  -- 结果 --")
for ln in io.open(p, encoding="utf-8"):
    if ln.strip().startswith("|") and "课 10" in ln and len(ln.split("|")) == 8:
        print("   " + ln.strip())

print()
print("=" * 60)
print(" 2. 阶段 4 概览 status 改为已完成")
print("=" * 60)
p = os.path.join(ROOT, "stages/4-怎么横向扩展/README.md")
t = io.open(p, encoding="utf-8").read()
if "status: 进行中" in t:
    t = t.replace("status: 进行中", "status: 已完成", 1)
    io.open(p, "w", encoding="utf-8", newline="\n").write(t)
    print("  已改: status: 进行中 -> 已完成")
elif "status: 已完成" in t:
    print("  已是已完成")
else:
    print("  [WARN] 未找到 status 字段")
print("  -- frontmatter --")
for ln in io.open(p, encoding="utf-8").read().split("\n")[:6]:
    print("   " + ln)

print()
print("=" * 60)
print(" 3. 阶段 4 概览补充下一阶段链接")
print("=" * 60)
t = io.open(p, encoding="utf-8").read()
OLD = "> 上一阶段：[阶段 3 凭什么快、凭什么省](../3-凭什么快凭什么省/README.md)"
NEW = ("> 上一阶段：[阶段 3 凭什么快、凭什么省](../3-凭什么快凭什么省/README.md)\n"
       "> 下一阶段：[阶段 5 生产落地](../5-生产落地/README.md)")
if OLD in t and "../5-生产落地/README.md" not in t:
    t = t.replace(OLD, NEW, 1)
    io.open(p, "w", encoding="utf-8", newline="\n").write(t)
    print("  已补充下一阶段链接")
else:
    print("  无需补充")

print()
print("=" * 60)
print(" 4. 全局校验：是否还有课 10 的『未开始』")
print("=" * 60)
import subprocess
r = subprocess.run(
    ["grep", "-rn", "课 10", "--include=*.md", ROOT],
    capture_output=True, text=True)
bad = 0
for ln in r.stdout.split("\n"):
    if "未开始" in ln or "⬜" in ln:
        print("  [残留] " + ln[:120])
        bad += 1
print("  残留数: %d" % bad)

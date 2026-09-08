#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""严格版误伤检查：只认"课文里逐字写了这个文件路径"，不认父目录。"""
import pathlib
import re
import subprocess

BASE = pathlib.Path("/mnt/d/projects/learning/prometheus")
LABS = BASE / "labs"

files = [p.relative_to(BASE).as_posix() for p in LABS.rglob("*") if p.is_file()]

proc = subprocess.run(["git", "check-ignore", "--stdin"],
                      input="\n".join(files), capture_output=True,
                      text=True, cwd=str(BASE))
ignored = set(proc.stdout.split())

# 收集课文中逐字出现的 labs 路径
refs = set()
for p in list(BASE.glob("*.md")) + list(BASE.glob("stages/**/*.md")):
    try:
        t = p.read_text(encoding="utf-8")
    except Exception:
        continue
    for m in re.findall(r"labs/[a-zA-Z0-9_/\-.]+", t):
        refs.add(m.rstrip("/.,)）"))

real_bad = []
for f in files:
    if f not in ignored:
        continue
    # 精确：课文逐字写了这个路径
    if f in refs:
        real_bad.append((f, "精确"))
        continue
    # 或者文件名在课文中以 labs/.../name 形式出现
    name = f.split("/")[-1]
    if any(r.endswith("/" + name) for r in refs):
        real_bad.append((f, "文件名"))

print("=" * 74)
print(f"严格误伤检查：{len(real_bad)} 个")
print("=" * 74)
for f, how in real_bad:
    print(f"    [{how}] {f}")

if not real_bad:
    print("    ✅ 无误伤")

# 反向：课文引用了但文件不存在（断链风险）
print("\n" + "=" * 74)
print("课文引用但文件不存在（若被忽略则风险）")
print("=" * 74)
missing = []
for r in sorted(refs):
    if "." not in r.split("/")[-1]:
        continue
    fp = BASE / r
    if not fp.exists():
        missing.append(r)
for m in missing[:20]:
    print(f"    ❌ {m}")
if not missing:
    print("    ✅ 全部存在")
else:
    print(f"    合计 {len(missing)} 个")

# 统计
isz = sum((BASE / f).stat().st_size for f in ignored)
tsz = sum((BASE / f).stat().st_size for f in files if f not in ignored)
print("\n" + "=" * 74)
print("最终账目")
print("=" * 74)
print(f"    提交 {len(files)-len(ignored)} 个  {tsz/1024:.1f} KB")
print(f"    忽略 {len(ignored)} 个  {isz/1024:.1f} KB")
print(f"    合计 {len(files)} 个  {(isz+tsz)/1024:.1f} KB")

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Phase 4 完整性检查：链接可达 + 12课纳入 + 实战项目收录 + 路径总览置顶。"""
import pathlib
import re

BASE = pathlib.Path("/mnt/d/projects/learning/prometheus")
P = BASE / "final-课程手册.md"
text = P.read_text(encoding="utf-8")

print("=" * 70)
print("Phase 4 汇总完整性检查")
print("=" * 70)
print(f"手册: {P.stat().st_size} 字节, {len(text.splitlines())} 行")

# 1. 链接可达性
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
links = LINK.findall(text)
bad = []
for label, target in links:
    if target.startswith(("http://", "https://", "#", "mailto:")):
        continue
    t = target.split("#")[0]
    if not t:
        continue
    fp = (P.parent / t).resolve()
    if not fp.exists():
        bad.append((label, target))
print(f"\n[1] 链接检查: 共 {len(links)} 条，断链 {len(bad)}")
for label, target in bad:
    print(f"    ❌ [{label}] -> {target}")

# 2. 12 课是否全部纳入
print("\n[2] 12 课纳入检查:")
import glob
lesson_files = sorted(BASE.glob("stages/*/lessons/lesson-*.md"))
missing = []
for lf in lesson_files:
    rel = str(lf.relative_to(BASE)).replace("\\", "/")
    if rel not in text:
        missing.append(rel)
print(f"    共 {len(lesson_files)} 课，未纳入 {len(missing)}")
for m in missing:
    print(f"    ❌ {m}")

# 3. 实战项目收录
print("\n[3] 实战项目收录:")
for key in ["多集群统一监控平台", "设计决策", "验收清单", "反例对照"]:
    print(f"    {'✅' if key in text else '❌'} {key}")

# 4. 路径总览 / 阶段总览置顶
print("\n[4] 开头结构（前 30 行标题）:")
for ln in text.splitlines()[:400]:
    if ln.startswith("# "):
        print(f"    {ln}")
    if "全局速查" in ln and ln.startswith("#"):
        break

# 5. 一图总结 / mermaid
print(f"\n[5] Mermaid 图: {text.count('```mermaid')} 个")

# 6. 三件套索引
print("\n[6] 三件套索引:")
for k in ["08-实战经验.md", "09-排障速查手册.md", "10-场景解法库.md"]:
    print(f"    {'✅' if k in text else '❌'} {k}")

# 7. 硬数字白名单抽查
print("\n[7] 关键实测数字抽查:")
for num in ["1.662", "2.96", "38 秒", "40 秒", "1199", "1450", "62162", "124347", "131.5", "2.69"]:
    print(f"    {'✅' if num in text else '⚠️ '} {num}")

print("\n" + "=" * 70)
ok = (not bad) and (not missing)
print("结论:", "✅ 全部通过" if ok else "❌ 有问题需修")
print("=" * 70)

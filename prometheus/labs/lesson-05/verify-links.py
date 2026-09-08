#!/usr/bin/env python3
"""课 5 交付后：全仓库 md 链接可达性检查 + 四处档案一致性校验。

长期记忆（mem_274a28_cff2e43）硬约束：
  InfluxDB/Prometheus 课程每课交付后必须校验链接可达性。
  2026-09-02 该校验曾一次性抓出 6 个阶段 overview 的返回链接层级错误（18 处）。
"""
import os
import re

ROOT = "/mnt/d/projects/learning/prometheus"

print("=" * 70)
print("链接可达性 + 档案一致性校验")
print("=" * 70)

# ---------- 1. 收集所有 md 文件 ----------
md_files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if not d.startswith(".")]
    for fn in filenames:
        if fn.endswith(".md"):
            md_files.append(os.path.join(dirpath, fn))
print("\n共 %d 个 md 文件" % len(md_files))

# ---------- 2. 检查所有相对链接 ----------
broken = []
checked = 0
for md in md_files:
    with open(md, encoding="utf-8") as f:
        content = f.read()
    for m in re.finditer(r"\[([^\]]*)\]\(([^)]+)\)", content):
        target = m.group(2).strip()
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        target = target.split("#")[0]
        if not target:
            continue
        full = os.path.normpath(os.path.join(os.path.dirname(md), target))
        checked += 1
        if not os.path.exists(full):
            broken.append((os.path.relpath(md, ROOT), target))

print("检查了 %d 个相对链接" % checked)
if broken:
    print("\n❌ 失效链接 %d 个：" % len(broken))
    for src, tgt in broken:
        print("   %s -> %s" % (src, tgt))
else:
    print("✅ 全部相对链接可达")

# ---------- 3. 四处档案一致性 ----------
print("\n" + "-" * 70)
print("四处档案回写一致性：")
checks = []

# (1) 学习档案：课 5 三行是否 ✅
with open(os.path.join(ROOT, "00-学习档案.md"), encoding="utf-8") as f:
    arc = f.read()
l5_done = arc.count("| 2 | 课 5 |") == 3 and "| 2 | 课 5 | 抑制、静默与时间窗口 | ✅ 已完成 |" in arc
checks.append(("① 00-学习档案.md 课5三行✅", l5_done))
checks.append(("① 断点更新到课6", "课 6《查询引擎与查询成本》" in arc))
checks.append(("① 评审记录含课5", "课 5《Alertmanager 深入》" in arc))
checks.append(("① 事实核查含课5", "Alertmanager 分组三参数" in arc))

# (2) 评审清单：课 5 勾选
with open(os.path.join(ROOT, "00-评审清单.md"), encoding="utf-8") as f:
    chk = f.read()
checks.append(("② 00-评审清单.md 课5已勾选",
               "- [x] 阶段 2·课 5《Alertmanager 深入》" in chk))
checks.append(("② 评审记录表含课5", "课 5《Alertmanager 深入》" in chk))

# (3) 阶段 2 overview
ov = os.path.join(ROOT, "stages/2-规则与告警/overview.md")
with open(ov, encoding="utf-8") as f:
    ovc = f.read()
checks.append(("③ 阶段2 overview 课5已勾选",
               "- [x] `lessons/lesson-05-Alertmanager深入.md`" in ovc))
checks.append(("③ 含课5交付纪要", "课 5 交付纪要" in ovc))

# (4) 课程目录 + 路径总览
with open(os.path.join(ROOT, "02-课程目录.md"), encoding="utf-8") as f:
    cat = f.read()
checks.append(("④ 02-课程目录.md 课5=✅",
               "lesson-05-Alertmanager深入.md) | ✅" in cat))
with open(os.path.join(ROOT, "01-学习路径总览.md"), encoding="utf-8") as f:
    tot = f.read()
checks.append(("④ 01-学习路径总览.md 进度已更新", "15/36" in tot))
checks.append(("④ 下一步指向课6", "下一步课 6" in tot))

for name, ok in checks:
    print("  [%s] %s" % ("OK " if ok else "MISS", name))

allok = not broken and all(ok for _, ok in checks)
print("\n" + "=" * 70)
print("总结: 链接 %s | 档案 %s" % (
    "全部可达" if not broken else "%d 个失效" % len(broken),
    "四处一致" if all(ok for _, ok in checks) else "有缺失"))
print("=" * 70)

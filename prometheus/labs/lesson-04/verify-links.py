#!/usr/bin/env python3
# 课 4 交付后：链接可达性 + 四处档案回写一致性检查
# 背景：2026-09-02 该校验一次性抓出六个阶段 overview 的返回链接层级错误（18 处）
import os
import re

ROOT = "/mnt/d/projects/learning/prometheus"
FAILS = []
WARNS = []

MD_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def check_file(path):
    """检查单个 md 文件里的本地链接是否可达。"""
    if not os.path.exists(path):
        return
    d = os.path.dirname(path)
    with open(path, encoding="utf-8") as f:
        content = f.read()
    for m in MD_LINK.finditer(content):
        target = m.group(2)
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        target = target.split("#")[0]
        if not target:
            continue
        full = os.path.normpath(os.path.join(d, target))
        if not os.path.exists(full):
            rel = os.path.relpath(path, ROOT)
            FAILS.append("%s -> %s (不可达)" % (rel, target))


print("=" * 70)
print("课 4 交付后校验")
print("=" * 70)

# ---- 1) 全仓库 md 链接可达性 ----
print()
print("### 1) 全仓库 Markdown 本地链接可达性 ###")
count = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    if ".git" in dirpath:
        continue
    for fn in filenames:
        if fn.endswith(".md"):
            check_file(os.path.join(dirpath, fn))
            count += 1
print("  已扫描 %d 个 md 文件" % count)
if FAILS:
    print("  ❌ 不可达链接 %d 处:" % len(FAILS))
    for f in FAILS:
        print("     %s" % f)
else:
    print("  ✅ 全部本地链接可达")

# ---- 2) 四处档案回写一致性 ----
print()
print("### 2) 四处档案回写一致性 ###")

checks = []

# (1) 00-学习档案.md：课 4 三行应为 ✅
p = os.path.join(ROOT, "00-学习档案.md")
with open(p, encoding="utf-8") as f:
    arch = f.read()
l4_rows = [ln for ln in arch.splitlines()
           if ln.startswith("| 2 | 课 4 |") and "✅" in ln]
checks.append(("学习档案 课4 三行已勾 ✅", len(l4_rows) == 3, "实测 %d 行" % len(l4_rows)))

l4_review = "课 4《规则引擎》" in arch
checks.append(("学习档案 评审记录含课4", l4_review, ""))

l4_env = "课 4 新增" in arch or "课 4 的容器" in arch
checks.append(("学习档案 环境备注含课4", l4_env, ""))

# (2) 00-评审清单.md：课 4 已勾选
p = os.path.join(ROOT, "00-评审清单.md")
with open(p, encoding="utf-8") as f:
    rl = f.read()
c1 = "- [x] 阶段 2·课 4《规则引擎》" in rl
checks.append(("评审清单 课4 已勾选", c1, ""))
c2 = rl.count("课 4《规则引擎》") >= 2
checks.append(("评审清单 记录表含课4摘要", c2, "出现 %d 次" % rl.count("课 4《规则引擎》")))

# (3) 阶段 2 overview：课 4 产出已勾选
p = os.path.join(ROOT, "stages/2-规则与告警/overview.md")
with open(p, encoding="utf-8") as f:
    ov = f.read()
c3 = "- [x] `lessons/lesson-04-规则引擎.md`" in ov
checks.append(("阶段2 overview 课4 已勾选", c3, ""))

# (4) 02-课程目录.md + 01-学习路径总览.md
p = os.path.join(ROOT, "02-课程目录.md")
with open(p, encoding="utf-8") as f:
    cat = f.read()
c4 = re.search(r"\|\s*4\s*\|\s*规则引擎\s*\|[^|]*\|\s*✅", cat) is not None
checks.append(("课程目录 课4 状态为 ✅", c4, ""))

p = os.path.join(ROOT, "01-学习路径总览.md")
with open(p, encoding="utf-8") as f:
    lp = f.read()
c5 = "课 4 已交付" in lp or "12/36" in lp
checks.append(("学习路径总览 进度已更新", c5, ""))

for name, ok, extra in checks:
    print("  %-32s %s %s" % (name, "✅" if ok else "❌", extra))

# ---- 3) 讲义完整性 ----
print()
print("### 3) 讲义结构完整性 ###")
p = os.path.join(ROOT, "stages/2-规则与告警/lessons/lesson-04-规则引擎.md")
with open(p, encoding="utf-8") as f:
    les = f.read()

sections = ["## 第一幕", "## 第二幕", "## 第三幕", "## 第四幕", "## 第五幕",
            "## 🐞 常见误区", "## 一图总结", "## 课后小测", "## 📌 本课速览",
            "## 🧭 课程导航", "## 🚀 下一批接力提示词", "## ✅ 评审结论"]
for s in sections:
    ok = s in les
    print("  %-28s %s" % (s, "✅" if ok else "❌ 缺失"))
    if not ok:
        FAILS.append("讲义缺少章节: %s" % s)

# 检查是否残留占位符
for ph in ["PHASE2-BATCH", "正文待生成", "待填充"]:
    if ph in les:
        FAILS.append("讲义残留占位符: %s" % ph)
        print("  ❌ 残留占位符: %s" % ph)

# 三个知识点都在
for kp in ["### 知识点 1：规则组与评估机制",
           "### 知识点 2：recording rules",
           "### 知识点 3：告警规则与状态机"]:
    if kp not in les:
        FAILS.append("讲义缺少知识点: %s" % kp)

print()
print("=" * 70)
total_fail = len([f for f in FAILS if "讲义" in f]) + len(
    [f for f in FAILS if "不可达" in f])
if total_fail == 0:
    print("✅ 全部校验通过")
else:
    print("❌ 发现 %d 处问题:" % total_fail)
    for f in FAILS:
        print("   %s" % f)
print("=" * 70)

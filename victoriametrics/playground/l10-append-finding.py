# -*- coding: utf-8 -*-
"""
课 10 补充：把「负载均衡结果抖动」这个新发现同步到档案与评审清单
（在已有课 10 记录后追加一条补充说明，不覆盖原记录）
"""
import io
import os

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"
TAG = "【补充实测】负载均衡结果抖动"

SUP = (
    "。另发现一处**未在讲义正文之外的独立验证**：vmauth 负载均衡到 dedup 配置"
    "不同的 vmselect 时，同一条查询连查 12 次得到 "
    "`5 10 5 10 5 10 5 10 5 10 5 10` 规律跳变"
    "（无 dedup 后端返 10，dedup 后端返 5）；"
    "viewer 因只配 1 个后端（无 dedup）稳定返 10，"
    "单后端 8489（dedup=5s）12 次全 5。"
    "这是**课 9 误区 4 的实锤证据**，已补入讲义第三幕（知识点 2 负载均衡段）、"
    "第四幕（新增实验 10）、🐞 常见误区（新增第 7b 条）与接力提示词基线"
)

print("=" * 60)
print(" 1. 学习档案：在课 10 评审记录末尾追加补充")
print("=" * 60)
p = os.path.join(ROOT, "00-学习档案.md")
t = io.open(p, encoding="utf-8").read()
lines = t.split("\n")
hit = False
for i, ln in enumerate(lines):
    if ln.startswith("|") and "课 10《多租户与 vmauth" in ln and TAG not in ln:
        # 在最后一个字段（结尾 | 前）插入补充
        if ln.rstrip().endswith("|"):
            lines[i] = ln.rstrip()[:-1].rstrip() + " " + SUP + " |"
        else:
            lines[i] = ln.rstrip() + " " + SUP
        hit = True
        break
io.open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("  追加: %s" % hit)

print()
print("=" * 60)
print(" 2. 评审清单：追加补充记录")
print("=" * 60)
p = os.path.join(ROOT, "00-评审清单.md")
t = io.open(p, encoding="utf-8").read()
lines = t.split("\n")
rec_idx = None
for i, ln in enumerate(lines):
    if ln.strip().startswith("## 评审记录"):
        rec_idx = i
        break
if rec_idx is not None:
    last_row = None
    for i in range(rec_idx, len(lines)):
        if lines[i].startswith("|"):
            last_row = i
        elif last_row is not None and lines[i].strip() == "":
            break
    if last_row is not None and not any(
        TAG in lines[i] for i in range(rec_idx, last_row + 1)
    ):
        ROW = (
            "| {d} | 课 10《多租户与 vmauth {tag} | 主 agent 内联 | 0 | "
            "vmauth 轮询到 dedup 配置不同的 vmselect 时，"
            "同一查询连查 12 次得 `5 10 5 10 5 10 5 10 5 10 5 10` 规律跳变；"
            "单后端对照稳定。已补入讲义三处 + 接力提示词 |"
        ).format(d=DATE, tag=TAG)
        lines.insert(last_row + 1, ROW)
        io.open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
        print("  追加成功")
    else:
        print("  已存在或位置异常")

print()
print("=" * 60)
print(" 3. 阶段 4 概览：追加该结论")
print("=" * 60)
p = os.path.join(ROOT, "stages/4-怎么横向扩展/README.md")
t = io.open(p, encoding="utf-8").read()
ANCHOR = "- **附带**：`-search.maxPointsPerTimeseries` 默认 30000（超限返 422）"
NEW = ANCHOR + "\n- **⚠️ 负载均衡结果抖动**：后端 dedup 配置不一致时，同一查询连查 12 次得 5/10 交替 → 必须统一所有 vmselect 的 dedup"
if ANCHOR in t and "负载均衡结果抖动" not in t:
    t = t.replace(ANCHOR, NEW, 1)
    io.open(p, "w", encoding="utf-8", newline="\n").write(t)
    print("  追加成功")
else:
    print("  已存在或锚点缺失")

print()
print("=" * 60)
print(" 4. 校验：讲义三处是否都已补入")
print("=" * 60)
p = os.path.join(ROOT, "stages/4-怎么横向扩展/10-多租户与vmauth.md")
t = io.open(p, encoding="utf-8").read()
checks = [
    ("第三幕 知识点2", "5 10 5 10 5 10 5 10 5 10 5 10"),
    ("第四幕 实验10", "### 实验 10：负载均衡导致结果不一致"),
    ("常见误区 7b", "### 7b. 负载均衡的后端 dedup 配置不一致"),
    ("接力提示词", "5/10 交替"),
]
for name, kw in checks:
    print("  %s %s" % ("[OK]  " if kw in t else "[MISS]", name))

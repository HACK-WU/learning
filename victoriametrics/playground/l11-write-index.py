#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 11 索引回写：课程目录 + 学习路径总览 + 阶段 5 README"""
import io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

CATALOG = r"/mnt/d/projects/learning/victoriametrics/02-课程目录.md"
OVERVIEW = r"/mnt/d/projects/learning/victoriametrics/01-学习路径总览.md"
STAGE5 = r"/mnt/d/projects/learning/victoriametrics/stages/5-生产落地/README.md"

# ---- 1. 课程目录 ----
txt = open(CATALOG, encoding='utf-8').read()
old = """- 课 11：vmagent 与 vmalert
  - 知识点 1：vmagent 抓取与持久化队列
  - 知识点 2：relabeling 与流式聚合
  - 知识点 3：vmalert 告警与 recording rules"""
new = """- 课 11：[vmagent 与 vmalert](stages/5-生产落地/11-vmagent与vmalert.md) ✅
  - 知识点 1：vmagent 抓取与持久化队列
  - 知识点 2：relabeling 与流式聚合
  - 知识点 3：vmalert 告警与 recording rules"""
if old in txt:
    txt = txt.replace(old, new)
    open(CATALOG, 'w', encoding='utf-8').write(txt)
    print("[OK] 课程目录：课 11 已加链接 + ✅")
elif new in txt:
    print("[SKIP] 课程目录已更新")
else:
    print("[WARN] 课程目录未匹配到课 11 条目")

# ---- 2. 学习路径总览 ----
txt2 = open(OVERVIEW, encoding='utf-8').read()
old2 = "- [ ] 阶段 5：生产落地（未开始）"
new2 = "- [ ] 阶段 5：生产落地（进行中，2026-09-02）— 课 11 已完成，剩课 12"
if old2 in txt2:
    txt2 = txt2.replace(old2, new2)
    print("[OK] 学习路径总览：阶段 5 状态已更新")
else:
    print("[SKIP] 阶段 5 状态已是最新")

old3 = "**总进度**：12 课中已完成 10 课（课 1–10），35 知识点中已完成 34 个。"
new3 = "**总进度**：12 课中已完成 11 课（课 1–11），35 知识点中已完成 37 个。"
if old3 in txt2:
    txt2 = txt2.replace(old3, new3)
    print("[OK] 学习路径总览：总进度已更新")
else:
    print("[SKIP] 总进度已是最新")

old4 = "> 更新时间：2026-09-02（课 5 交付后同步）"
new4 = "> 更新时间：2026-09-02（课 11 交付后同步）"
if old4 in txt2:
    txt2 = txt2.replace(old4, new4)
    print("[OK] 学习路径总览：更新时间已刷新")

open(OVERVIEW, 'w', encoding='utf-8').write(txt2)

# ---- 3. 阶段 5 README：课 11 标 ✅ ----
txt3 = open(STAGE5, encoding='utf-8').read()
old5 = "| **课 11** | vmagent 与 vmalert | ⬜ 未开始 |"
new5 = "| **课 11** | [vmagent 与 vmalert](11-vmagent与vmalert.md) | ✅ 已完成（2026-09-02） |"
if old5 in txt3:
    txt3 = txt3.replace(old5, new5)
    open(STAGE5, 'w', encoding='utf-8').write(txt3)
    print("[OK] 阶段 5 README：课 11 已标 ✅ + 链接")
elif new5 in txt3:
    print("[SKIP] 阶段 5 README 已更新")
else:
    print("[WARN] 阶段 5 README 未匹配到课 11 行")

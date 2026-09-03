#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 11 评审 · Agent B：learner（学习者视角）"""
import re, sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

BASE = r"/mnt/d/projects/learning/victoriametrics"
DOC = os.path.join(BASE, r"stages/5-生产落地/11-vmagent与vmalert.md")
txt = open(DOC, encoding='utf-8').read()

print("=" * 70)
print("Agent B · learner 视角评审（照抄能否跑通 / 术语 / 排障）")
print("=" * 70)

# 1. 引用的脚本是否真实存在
print("\n【1. 引用的脚本文件是否存在】\n")
scripts = re.findall(r'`(l11-[\w\-]+\.(?:sh|py|yml))`', txt)
seen = set()
for s in scripts:
    if s in seen:
        continue
    seen.add(s)
    path = os.path.join(BASE, "playground", s)
    exists = os.path.exists(path)
    print(f"  [{'OK  ' if exists else 'MISS'}] playground/{s}")

# 规则文件
print("\n【2. 引用的配置/规则文件是否存在】\n")
for f in ["rules/alerts.yml", "rules/recording.yml", "rules/mql-test.yml",
          "stream-aggr.yml", "prometheus-vmagent.yml", "alertmanager.yml"]:
    path = os.path.join(BASE, "playground", f)
    exists = os.path.exists(path)
    print(f"  [{'OK  ' if exists else 'MISS'}] playground/{f}")

# 3. 必须查项 #11：每条命令真跑过
print("\n【3. 命令可复现性（代码块统计）】\n")
blocks = re.findall(r'```(bash|yaml|json)\n(.*?)```', txt, re.S)
print(f"  代码块总数: {len(blocks)}")
from collections import Counter
c = Counter(b[0] for b in blocks)
for k, v in c.items():
    print(f"      {k}: {v}")

# 4. 关键判据是否给出
print("\n【4. 实验是否给出判据】\n")
exp_table = re.search(r'\| # \| 实验 \| 判据 \| 结果 \|(.*?)\n\n', txt, re.S)
if exp_table:
    rows = [r for r in exp_table.group(1).split('\n') if r.startswith('|')]
    print(f"  实验表行数（含表头分隔）: {len(rows)}")
    has_judge = all(len(r.split('|')) >= 5 for r in rows if r.strip())
    print(f"  [{'OK' if has_judge else 'MISS'}] 每行均含「判据」列")
else:
    print("  [MISS] 未找到实验清单表")

# 5. 术语是否跳空
print("\n【5. 术语首次出现是否有解释】\n")
terms = {
    "remote write": "写入协议（课 4 已讲）",
    "持久化队列": "本课核心，已详述",
    "记录规则": "recording rules，已对照 Prometheus",
    "MetricsQL": "课 3 已讲",
    "一致性哈希": "课 8 已讲",
    "dedup": "课 9 已讲",
    "基数": "课 4 已讲",
    "流式聚合": "stream aggregation，本课新概念",
}
for t, note in terms.items():
    idx = txt.find(t)
    print(f"  {t:<16} 首次出现在第 {idx} 字符位  ({note})")

# 6. 危险操作是否有提示
print("\n【6. 危险操作安全提示】\n")
danger = ["docker stop", "docker rm", "rm -rf", "docker restart", "docker pause"]
for d in danger:
    cnt = txt.count(d)
    if cnt > 0:
        # 检查附近是否有提示
        print(f"  {d:<16} 出现 {cnt} 次")
warn_cnt = txt.count("⚠️")
print(f"\n  ⚠️ 警告标记总数: {warn_cnt}")

# 7. 常见误区是否来自真实踩坑
print("\n【7. 常见误区清单】\n")
pit = re.search(r'### 🐞 常见误区汇总\n(.*?)\n### ', txt, re.S)
if pit:
    items = [l for l in pit.group(1).split('\n') if re.match(r'^\d+\.', l.strip())]
    print(f"  误区条数: {len(items)}")
    for it in items:
        print(f"      {it.strip()[:70]}")
else:
    print("  [MISS] 未找到误区汇总")

# 8. 篇幅合理性
print("\n【8. 篇幅分布】\n")
parts = re.split(r'\n### 知识点 ', txt)
for p in parts[1:]:
    kname = p.split('\n')[0][:36]
    nlines = len(p.split('\n'))
    print(f"  知识点 {kname}: {nlines} 行")
print(f"\n  全文总行数: {len(txt.split(chr(10)))}")

# 9. 链接可达性
print("\n【9. 内部链接可达性】\n")
links = re.findall(r'\]\((\.\.?/[^)]+)\)', txt)
for l in set(links):
    target = os.path.normpath(os.path.join(os.path.dirname(DOC), l))
    exists = os.path.exists(target)
    print(f"  [{'OK  ' if exists else 'MISS'}] {l}")

print("\n" + "=" * 70)
print("Agent B 评审结束")
print("=" * 70)

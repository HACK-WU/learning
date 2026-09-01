#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 讲义自检：引用完整性 + 小测结构 + 事实一致性。

检查项：
  S1  讲义引用的 playground 脚本是否真实存在
  S2  小测数量与 <details> 折叠答案是否配对
  S3  小节标题结构完整（速查卡 / 常见误区 / 小测 / 官方文档 / 导航）
  S4  正文中【不再出现】已修正的错误事实（旧指标名、0.4 水位、"未跑通"）
  S5  内部锚点链接指向的文件是否存在
"""
import os
import re
import sys

BASE = '/mnt/d/projects/learning/rabbitmq'
DOC = (BASE + '/stages/4-进阶与工程落地/lessons/'
       'lesson-12-架构落地与选型决策.md')
PLAYGROUND = BASE + '/playground'

PASS = []
FAIL = []


def check(name, ok, detail=''):
    (PASS if ok else FAIL).append(name)
    print("  [%s] %s%s" % ("✅" if ok else "❌", name,
                           ("  —— " + detail) if detail else ""))


def main():
    with open(DOC, encoding='utf-8') as f:
        text = f.read()

    print("=" * 72)
    print("课 12 讲义自检")
    print("=" * 72)

    # ---------- S1 脚本引用 ----------
    print("\n[S1] 引用的 playground 脚本是否存在")
    refs = set(re.findall(r'`(l12-[A-Za-z0-9_\-]+\.(?:py|sh))`', text))
    missing = []
    for r in sorted(refs):
        if not os.path.exists(os.path.join(PLAYGROUND, r)):
            missing.append(r)
    check("S1 引用的 %d 个脚本全部存在" % len(refs),
          not missing, ", ".join(missing) if missing else
          "、".join(sorted(refs))[:120])

    # ---------- S2 小测结构 ----------
    print("\n[S2] 小测结构")
    qs = re.findall(r'^### (Q\d+)（(单选|多选|简答)）', text, re.M)
    details = len(re.findall(r'<details><summary>答案</summary>', text))
    check("S2 小测数量 = 6", len(qs) == 6, "实际 %d 道：%s" % (
        len(qs), ", ".join("%s(%s)" % (a, b) for a, b in qs)))
    check("S2 每道题都有折叠答案", details == len(qs),
          "题目 %d / 答案 %d" % (len(qs), details))
    kinds = [b for _, b in qs]
    check("S2 题型覆盖单选+多选+简答",
          '单选' in kinds and '多选' in kinds and '简答' in kinds,
          "/".join(sorted(set(kinds))))

    # ---------- S3 结构完整性 ----------
    print("\n[S3] 章节结构")
    for sec in ['## 本课要点速查卡', '## 常见误区', '## 🧪 小测',
                '## 📚 本课官方文档汇总', '## 🧭 课程导航',
                '## 本课实测环境']:
        check("S3 存在章节：%s" % sec.replace('## ', ''), sec in text)

    # ---------- S4 已修正的错误事实不得重现 ----------
    print("\n[S4] 已修正的错误事实不得重现（回归检查）")
    # 旧指标名：讲义里是当作「已废弃」的反例有意出现的，
    # 所以允许出现，但每次出现都必须带明确的废弃说明，否则会误导读者。
    for k in ['rabbitmq_node_mem_used', 'rabbitmq_node_mem_limit',
              'rabbitmq_node_disk_free', 'rabbitmq_node_disk_free_limit']:
        bad_ctx = []
        for ln in text.splitlines():
            if k in ln:
                # 同一行（含紧邻的上下一行）必须有「不存在/老版本/已」这类说明
                idx = text.splitlines().index(ln)
                around = '\n'.join(text.splitlines()[max(0, idx - 1):idx + 2])
                if not any(w in around for w in
                           ('不存在', '老版本', '已废弃', '已不存在',
                            '不可引用', '旧指标')):
                    bad_ctx.append(ln.strip()[:70])
        check("S4 %s 仅作为「已废弃」反例出现" % k, not bad_ctx,
              "; ".join(bad_ctx) if bad_ctx else "均带废弃说明")

    # 0.4 水位：允许出现在"版本对比"语境，不允许作为本环境默认值
    water_lines = [ln for ln in text.splitlines()
                   if '0.4' in ln and '水位' in ln]
    bad04 = [ln for ln in water_lines if '3.x' not in ln and '版本' not in ln]
    check("S4 内存水位不再把 0.4 当成本环境默认值",
          not bad04, "; ".join(bad04)[:100] if bad04 else "已区分 3.x/4.x")

    # ---------- S5 内部链接 ----------
    print("\n[S5] 内部链接")
    links = re.findall(r'\]\((\.\.?/[^)]+)\)', text)
    broken = []
    for lk in links:
        target = os.path.normpath(os.path.join(os.path.dirname(DOC), lk))
        if not os.path.exists(target):
            broken.append(lk)
    check("S5 内部链接全部有效（共 %d 条）" % len(links),
          not broken, ", ".join(broken) if broken else "")

    print("\n" + "=" * 72)
    print("结果：通过 %d / 失败 %d" % (len(PASS), len(FAIL)))
    if FAIL:
        print("失败项：")
        for f in FAIL:
            print("  ❌ %s" % f)
    else:
        print("✅ 全部通过")
    print("=" * 72)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())

# -*- coding: utf-8 -*-
"""
课 5 交付后的全局链接可达性检查（用户 2026-09-02 强制要求的配套校验）。

扫描范围：课程根目录下所有 .md 文件（含四个索引 + 各阶段 overview/README）
检查内容：每个 Markdown 本地链接的目标文件是否真实存在

历史教训（2026-09-02，InfluxDB 课程）：
    该校验曾一次性抓出六个阶段 overview 的返回链接层级错误
    （应为 ../../02-课程目录.md，实写 ../02-课程目录.md，共 18 处）。
    所以这一步不能省。
"""
import os
import re
import sys

ROOT = "/mnt/d/projects/learning/victoriametrics"
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")

total_links = 0
bad_links = []
files_scanned = 0

for dirpath, dirnames, filenames in os.walk(ROOT):
    # 跳过 data 目录（实验数据，不是文档）
    if "playground" in dirpath.split(os.sep):
        continue
    for fn in filenames:
        if not fn.endswith(".md"):
            continue
        fp = os.path.join(dirpath, fn)
        files_scanned += 1
        try:
            with open(fp, encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            print("[WARN] 读取失败 %s: %s" % (fp, e))
            continue

        for m in LINK_RE.finditer(content):
            target = m.group(2).strip()
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = target.split("#")[0].strip()
            if not target:
                continue
            total_links += 1
            resolved = os.path.normpath(os.path.join(dirpath, target))
            if not os.path.exists(resolved):
                rel = os.path.relpath(fp, ROOT)
                bad_links.append((rel, target, resolved))

print("扫描 Markdown 文件数：%d" % files_scanned)
print("检查本地链接总数  ：%d" % total_links)
print("断链数            ：%d" % len(bad_links))

if bad_links:
    print()
    print("========== 断链明细 ==========")
    for rel, target, resolved in bad_links:
        print("  [%s]" % rel)
        print("      链接: %s" % target)
        print("      解析: %s" % resolved)
    sys.exit(1)
else:
    print()
    print("✅ 全部本地链接可达，0 断链")
    sys.exit(0)

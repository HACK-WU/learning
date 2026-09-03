#!/usr/bin/env python3
"""检查评审清单中课 5 记录的实际内容。"""
import io

P = "/mnt/d/projects/learning/victoriametrics/00-评审清单.md"
with io.open(P, "r", encoding="utf-8") as f:
    text = f.read()

# 找到含 "课 5" 的行
for i, line in enumerate(text.split("\n"), 1):
    if "课 5" in line:
        print("行 {}: 长度={}".format(i, len(line)))
        print("  内容前 300 字:")
        print("   ", line[:300])
        print("  内容后 200 字:")
        print("   ", line[-200:])
        print()

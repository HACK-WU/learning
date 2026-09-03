# -*- coding: utf-8 -*-
"""课 5 讲义繁简复核：确认「本課」已全部转为「本课」。"""
import sys

F = "/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/5-存储引擎MergeSet与磁盘结构.md"
with open(F, encoding="utf-8") as f:
    t = f.read()

trad = t.count("本課")
simp = t.count("本课")
print("繁体[本課] 剩余: %d" % trad)
print("简体[本课] 总数: %d" % simp)

# 顺带扫一遍其它常见繁体字，确认没有别处漏网
others = ["課件", "存儲", "壓縮", "機制", "數據", "實測", "目錄", "時間"]
found = [(w, t.count(w)) for w in others if t.count(w) > 0]
if found:
    print("其它繁体残留: %s" % found)
else:
    print("其它繁体残留: 无")

sys.exit(0 if trad == 0 else 1)

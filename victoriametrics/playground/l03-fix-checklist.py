#!/usr/bin/env python3
"""修复 00-评审清单.md：删除表格中的空行，并补回被误删的标题。"""
import io

P = "/mnt/d/projects/learning/victoriametrics/00-评审清单.md"

with io.open(P, "r", encoding="utf-8") as f:
    lines = f.read().split("\n")

out = []
i = 0
while i < len(lines):
    line = lines[i]
    # 在表格区域（以 | 开头）内跳过空行
    if line.strip() == "":
        # 前瞻：下一非空行是否以 | 开头；回看：上一非空行是否以 | 开头
        prev = None
        for j in range(len(out) - 1, -1, -1):
            if out[j].strip() != "":
                prev = out[j]
                break
        nxt = None
        for j in range(i + 1, len(lines)):
            if lines[j].strip() != "":
                nxt = lines[j]
                break
        if (prev and prev.lstrip().startswith("|")
                and nxt and nxt.lstrip().startswith("|")):
            i += 1
            continue
    out.append(line)
    i += 1

# 删除误插入的「评审报警真伪判定记录（见下表）」数据行
out = [l for l in out if "评审报警真伪判定记录（见下表）" not in l]

# 补回标题（若缺失）
if not any(l.strip() == "### 评审报警真伪判定记录" for l in out):
    for idx, l in enumerate(out):
        if l.startswith("| 日期 | 报警来源 |"):
            out.insert(idx, "### 评审报警真伪判定记录")
            out.insert(idx + 1, "")
            break

with io.open(P, "w", encoding="utf-8") as f:
    f.write("\n".join(out))

print("修复完成")

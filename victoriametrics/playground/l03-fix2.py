#!/usr/bin/env python3
"""在评审清单的两个表格之间补空行，保证 Markdown 渲染正确。"""
import io

P = "/mnt/d/projects/learning/victoriametrics/00-评审清单.md"
with io.open(P, "r", encoding="utf-8") as f:
    text = f.read()

old = """| 2026-09-02 | 课 3《MetricsQL：站在 PromQL 肩膀上》 | 主 agent 内联（pedagogy + learner） | 0 | **实测推翻直觉×2**"""
if old in text:
    print("课 3 行已存在")

target = "### 评审报警真伪判定记录"
if target in text:
    idx = text.index(target)
    before = text[:idx]
    if not before.endswith("\n\n"):
        text = text[:idx].rstrip("\n") + "\n\n" + text[idx:]
        with io.open(P, "w", encoding="utf-8") as f:
            f.write(text)
        print("已补空行")
    else:
        print("空行已存在，无需修改")
else:
    print("未找到目标标题")

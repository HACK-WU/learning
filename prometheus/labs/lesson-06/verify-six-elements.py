"""核验：pedagogy 脚本报的「知识点2缺六要素」是真问题还是定位错误？

脚本用 text.find("知识点 2") 取第一次出现位置。若该字符串在别处先出现，
段落切分会错位，导致误报。必须回读原文确认。
"""
import re

PATH = ("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/"
        "lessons/lesson-06-查询引擎与查询成本.md")

with open(PATH, encoding="utf-8") as f:
    text = f.read()

six = ["一句话定义", "直觉建立", "核心原理", "示例演示", "常见误区", "一句话记住"]

print("== 1. 「知识点 N」标题的所有出现位置 ==")
for m in re.finditer(r"#{2,4}\s*知识点\s*\d", text):
    line_no = text[:m.start()].count("\n") + 1
    print(f"   行 {line_no}: {m.group(0)}")

print()
print("== 2. 「知识点 2」这个子串在全文的出现位置 ==")
for m in re.finditer(r"知识点\s*2", text):
    line_no = text[:m.start()].count("\n") + 1
    ctx = text.splitlines()[line_no - 1][:70]
    print(f"   行 {line_no}: {ctx}")

print()
print("== 3. 按标题切分，逐知识点核验六要素 ==")
# 找到所有知识点标题
heads = [(m.start(), m.group(0)) for m in re.finditer(r"#{2,4}\s*知识点\s*\d", text)]
for i, (pos, title) in enumerate(heads):
    end = heads[i + 1][0] if i + 1 < len(heads) else len(text)
    seg = text[pos:end]
    print(f"\n   --- {title.strip()} （段落长度 {len(seg)} 字符）---")
    for e in six:
        line_no = None
        for m in re.finditer(re.escape(e), seg):
            line_no = text[:pos + m.start()].count("\n") + 1
            break
        mark = f"行 {line_no}" if line_no else "  ★缺失"
        print(f"      {e:<8} {mark}")

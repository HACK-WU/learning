"""核验 learner 视角的 4 个 P0：是否都在可执行命令里？

判据：
- 若 .+ 出现在**可执行命令块**里 → 真 P0（读者照抄会命中 0 条）
- 若 .+ 出现在**说明性文字**里（讲原理，不是让你抄的命令）→ 脚本误报

必须回读原文确认，不能凭脚本判断。
"""
import re

PATH = ("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/"
        "lessons/lesson-06-查询引擎与查询成本.md")

with open(PATH, encoding="utf-8") as f:
    text = f.read()

lines = text.splitlines()

# 建立"行号 → 是否在 bash 代码块内"的映射
in_code = {}
inside = False
lang = None
for i, ln in enumerate(lines, 1):
    if ln.strip().startswith("```"):
        if not inside:
            inside = True
            lang = ln.strip()[3:].strip()
        else:
            inside = False
            lang = None
        in_code[i] = False
        continue
    in_code[i] = inside and (lang in ("bash", "yaml", "promql", ""))

targets = [147, 354, 788, 794]
print("=" * 70)
print("核验：4 处 .+ 分别在哪里？")
print("=" * 70)
for t in targets:
    print(f"\n--- 行 {t} ---")
    for d in range(-2, 3):
        n = t + d
        if 1 <= n <= len(lines):
            mark = "★" if d == 0 else " "
            inc = "[代码]" if in_code.get(n) else "[正文]"
            print(f"  {mark} 行{n} {inc} {lines[n-1][:88]}")

print()
print("=" * 70)
print("结论：逐个判定")
print("=" * 70)
for t in targets:
    inblk = in_code.get(t, False)
    # 找最近的 ```bash 块开始
    start = t
    while start > 1 and not lines[start - 1].strip().startswith("```"):
        start -= 1
    blk_lang = lines[start - 1].strip()[3:].strip() if start > 1 else "?"
    verdict = "真P0（可执行命令）" if (inblk and blk_lang == "bash") else "误报（正文说明）"
    print(f"  行 {t}: 在代码块内={inblk} 块语言={blk_lang!r} → {verdict}")

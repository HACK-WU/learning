"""排查：进度勾选为什么没替换成功"""
import io
import os

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TARGET = os.path.join(SUBROOT, "overview.md")

with io.open(TARGET, encoding="utf-8") as f:
    lines = f.readlines()

print("=== 学习进度段落 ===")
for i, l in enumerate(lines, 1):
    if "课 9" in l or "课 8" in l:
        print(f"{i:4d}| {l.rstrip()[:120]}")

print()
print("=== 是否存在番外行 ===")
print("课 9 番外 出现次数:",
      sum(1 for l in lines if "课 9 番外" in l))

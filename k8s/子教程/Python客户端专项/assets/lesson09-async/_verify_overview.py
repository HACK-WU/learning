"""核验 overview.md 插入后的实际 UTF-8 内容（终端 GBK 会显示乱码，不可信）"""
import io
import os

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TARGET = os.path.join(SUBROOT, "overview.md")

with io.open(TARGET, encoding="utf-8") as f:
    lines = f.readlines()

print("总行数:", len(lines))
hits = [i + 1 for i, l in enumerate(lines) if "课 9 番外" in l]
print("含『课 9 番外』的行号:", hits)

for i in hits:
    l = lines[i - 1]
    print(f"--- 行 {i} 前 200 字 ---")
    print(l[:200])

# 检查表格结构是否完整（每行应以 | 开头结尾，且列数一致）
print()
print("=== 课程表结构校验 ===")
tbl = [(i + 1, l) for i, l in enumerate(lines)
       if l.startswith("| [课") or l.startswith("| [番外")]
print("课程/番外行数:", len(tbl))
bad = []
for ln, l in tbl:
    if not l.rstrip().endswith("|"):
        bad.append((ln, "未以 | 结尾"))
print("结构异常行:", bad if bad else "无")

# 关键结论词是否都在
keys = ["429 恒为 0", "2.69x", "0.583", "ApplyResult",
        "attached to a different loop", "kube-root-ca.crt"]
print()
print("=== 关键结论词校验 ===")
for k in keys:
    print(f"  {k:36s}: {'✓' if any(k in l for _, l in tbl) else '✗ 缺失'}")

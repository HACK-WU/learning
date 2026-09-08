import os
import re

ROOT = "/mnt/d/projects/learning/prometheus/stages"
RETURN_LINK = re.compile(r"\]\((\.\./)+0[12]-")

print("=== 检查各课骨架中回根目录的链接层级是否正确 ===")
print("（课文件位于 stages/<阶段>/lessons/ 下，回根目录应为 ../../../）")
print()

issues = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    for fn in sorted(filenames):
        if not fn.endswith(".md") or fn == "overview.md":
            continue
        path = os.path.join(dirpath, fn)
        with open(path, encoding="utf-8") as f:
            content = f.read()
        rel = os.path.relpath(path, "/mnt/d/projects/learning/prometheus")
        for m in RETURN_LINK.finditer(content):
            link = m.group(0)
            ups = link.count("../")
            if ups != 3:
                print("  [层级错] %s : %s（应为 ../../../）" % (rel, link))
                issues += 1
            else:
                print("  [正确]   %s : %s" % (rel, link))

print()
print("层级错误数: %d" % issues)

"""校验全库 Markdown 的本地链接与图片引用是否存在，并校验 SVG 合法性。

用法（在任意目录执行都可以）：
    python3 distributed-python/playground/check_links.py

退出码 0 表示全部通过，1 表示存在死链或非法 SVG。
"""
import os
import re
import sys
import xml.dom.minidom

# 脚本在 <教程根>/playground/ 下，教程根是它的上一级
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SKIP_DIRS = {".git", "__pycache__", "node_modules"}

md_files = []
svg_files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
    for fn in filenames:
        full = os.path.join(dirpath, fn)
        if fn.endswith(".md"):
            md_files.append(full)
        elif fn.endswith(".svg"):
            svg_files.append(full)

img_re = re.compile(r"!\[[^\]]*\]\(([^)]+)\)")
link_re = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
EXTERNAL = ("http://", "https://", "mailto:", "#")

broken = []
total_links = 0
for path in md_files:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for m in img_re.finditer(text):
        target = m.group(1).strip()
        if target.startswith(EXTERNAL):
            continue
        total_links += 1
        resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
        if not os.path.exists(resolved):
            broken.append((os.path.relpath(path, ROOT), "IMG", target))
    for m in link_re.finditer(text):
        target = m.group(1).strip().split("#")[0]
        if not target or target.startswith(EXTERNAL):
            continue
        total_links += 1
        resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
        if not os.path.exists(resolved):
            broken.append((os.path.relpath(path, ROOT), "LINK", target))

svg_bad = []
for path in svg_files:
    try:
        xml.dom.minidom.parse(path)
    except Exception as e:
        svg_bad.append((os.path.relpath(path, ROOT), str(e)[:100]))

print(f"Markdown 文件数：{len(md_files)}")
print(f"本地引用检查数：{total_links}")
print(f"死链/缺图：{len(broken)}")
for item in broken:
    print(f"  ✗ {item[0]} [{item[1]}] -> {item[2]}")
print(f"SVG 文件数：{len(svg_files)}")
print(f"SVG 非法：{len(svg_bad)}")
for item in svg_bad:
    print(f"  ✗ {item[0]} -> {item[1]}")

sys.exit(1 if (broken or svg_bad) else 0)

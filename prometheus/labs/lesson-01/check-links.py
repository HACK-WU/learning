import os
import re
import sys

ROOT = "/mnt/d/projects/learning/prometheus"
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")

total = 0
broken = []


def check(md_path):
    global total
    with open(md_path, encoding="utf-8") as f:
        content = f.read()
    base = os.path.dirname(md_path)
    for text, target in LINK_RE.findall(content):
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        target = target.split("#")[0].strip()
        if not target:
            continue
        total += 1
        resolved = os.path.normpath(os.path.join(base, target))
        if not os.path.exists(resolved):
            broken.append((os.path.relpath(md_path, ROOT), text, target, resolved))


for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".git",)]
    for fn in filenames:
        if fn.endswith(".md"):
            check(os.path.join(dirpath, fn))

print("总本地链接: %d" % total)
print("断链数: %d" % len(broken))
for src, text, target, resolved in broken:
    print("  [断链] %s: [%s](%s) -> %s" % (src, text, target, resolved))
sys.exit(1 if broken else 0)

"""子教程骨架链接可达性检查。

沿用既有的"交付后跑链接可达性检查"铁律（见 00-评审清单.md 第 30 项）。
检查范围：子教程内所有 md 文件的相对链接。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

checked = 0
broken = []

md_files = sorted(ROOT.rglob("*.md"))
print(f"扫描 {len(md_files)} 个 md 文件（根目录 {ROOT}）")
print()

for md in md_files:
    text = md.read_text(encoding="utf-8")
    for m in LINK_RE.finditer(text):
        name, target = m.group(1), m.group(2).strip()
        if not target or target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        target_path = target.split("#")[0].strip()
        if not target_path:
            continue
        resolved = (md.parent / target_path).resolve()
        checked += 1
        if not resolved.exists():
            broken.append((str(md.relative_to(ROOT)), name, target_path))

print(f"共检查 {checked} 条本地链接")
print()

if broken:
    print(f"❌ 发现 {len(broken)} 条断链：")
    for src, name, tgt in broken:
        print(f"  [{src}]  '{name}' -> {tgt}")
    sys.exit(1)
else:
    print("✅ 零断链")

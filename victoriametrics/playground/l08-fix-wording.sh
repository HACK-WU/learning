#!/bin/bash
# 修正课 8 档案中「✅ 未开始」的措辞矛盾
cd /mnt/d/projects/learning/victoriametrics || exit 1
F="00-学习档案.md"
python3 - "$F" <<'PY'
import io, sys
f = sys.argv[1]
lines = io.open(f, encoding="utf-8").read().split("\n")
n = 0
for i, ln in enumerate(lines):
    if "课 8" in ln and "✅ 未开始" in ln:
        lines[i] = ln.replace("✅ 未开始", "✅ 已完成").replace("| - | - |", "| 2026-09-02 | 见讲义 |")
        n += 1
io.open(f, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("  修正 %d 处" % n)
PY
echo
echo "-- 修正结果 --"
grep '课 8' "$F" | head -6

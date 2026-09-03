#!/bin/bash
# 排查：课 10 进度表为何勾选 0 处 + 阶段状态为何没改
cd /mnt/d/projects/learning/victoriametrics || exit 1

echo "=== 1. 学习档案中课 10 的行 ==="
grep -n '课 10' 00-学习档案.md

echo
echo "=== 2. 该行的原始结构（用 | 分隔显示）==="
python3 - <<'PY'
import io
for ln in io.open("00-学习档案.md", encoding="utf-8"):
    if "课 10" in ln and ln.strip().startswith("|"):
        parts = ln.split("|")
        print("  共 %d 段:" % len(parts))
        for j, p in enumerate(parts):
            print("    [%d] %r" % (j, p.strip()))
        break
PY

echo
echo "=== 3. 阶段 4 概览中『进行中』的位置 ==="
grep -n '进行中\|阶段状态\|状态' 'stages/4-怎么横向扩展/README.md' | head -8

echo
echo "=== 4. 阶段 4 概览头部 ==="
head -20 'stages/4-怎么横向扩展/README.md'

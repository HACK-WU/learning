#!/usr/bin/env bash
set -uo pipefail
cd /mnt/d/projects/learning/prometheus/stages/3-规模化与生态/lessons
echo "=== 手工核验 4 条被报死链的链接 ==="
for f in ../../../../labs/lesson-09/DATA.md ../../00-学习档案.md ../../02-课程目录.md ../lesson-08-联邦与全局视图.md; do
  if [ -f "$f" ]; then
    echo "  OK    $f  ->  $(basename "$(realpath "$f")")"
  else
    echo "  MISS  $f"
  fi
done
echo
echo "=== 这些目录的真实内容 ==="
echo "-- labs/lesson-09/ --"; ls /mnt/d/projects/learning/prometheus/labs/lesson-09/*.md 2>/dev/null | head -3
echo "-- 仓库根 --"; ls /mnt/d/projects/learning/prometheus/*.md 2>/dev/null | head -5
echo "-- stages/3/lessons/ --"; ls /mnt/d/projects/learning/prometheus/stages/3-规模化与生态/lessons/ 2>/dev/null

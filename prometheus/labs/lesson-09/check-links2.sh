#!/usr/bin/env bash
set -uo pipefail
cd /mnt/d/projects/learning/prometheus/stages/3-规模化与生态/lessons
echo "=== 核验全部 6 条链接 ==="
for f in ../../../00-学习档案.md ../../../02-课程目录.md ../../../labs/lesson-09/DATA.md \
         ../../4-生产运维/overview.md ../overview.md ./lesson-08-联邦与全局视图.md; do
  [ -f "$f" ] && echo "  OK    $f" || echo "  MISS  $f"
done

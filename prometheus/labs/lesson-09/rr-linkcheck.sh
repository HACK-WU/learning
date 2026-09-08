#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus
echo "=== 层级核验 ==="
ls -la $D/labs/lesson-09/RR-DATA.md 2>&1
echo "--- 从课7讲义位置解析 ../../../labs/lesson-09/RR-DATA.md ---"
REAL=$(cd $D/stages/3-规模化与生态/lessons && cd ../../../labs/lesson-09 && pwd)
echo "resolved: $REAL"
[ -f "$REAL/RR-DATA.md" ] && echo "LINK OK" || echo "LINK BROKEN"

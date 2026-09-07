#!/bin/bash
D=/mnt/d/projects/learning/grafana
echo "=== 1. 课 12 行数与大小 ==="
wc -l -c "$D/stages/4-管得住/lessons/lesson-12-性能、高可用与升级运维.md"
echo

echo "=== 2. 02-课程目录.md 中课 12 当前写法 ==="
grep -n "课 12\|lesson-12" "$D/02-课程目录.md" || echo "  (未找到)"
echo

echo "=== 3. 01-学习路径总览.md 中阶段4/课12 ==="
grep -n "课 12\|lesson-12\|管得住" "$D/01-学习路径总览.md" || echo "  (未找到)"
echo

echo "=== 4. 00-学习档案.md 中课 12 ==="
grep -n "课 12\|lesson-12" "$D/00-学习档案.md" || echo "  (未找到)"
echo

echo "=== 5. 阶段 4 overview 中课 12 产出行 ==="
grep -n "lesson-12" "$D/stages/4-管得住/overview.md"
echo

echo "=== 6. 00-评审清单.md 中课 12 条目（注意有重复）==="
grep -n "课 12" "$D/00-评审清单.md"

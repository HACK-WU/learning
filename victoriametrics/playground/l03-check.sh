#!/usr/bin/env bash
# 课 3 交付后校验：目录结构、档案更新、结构完整性、导航链接
set -u
BASE="/mnt/d/projects/learning/victoriametrics"
L3="$BASE/stages/2-数据怎么进来怎么查/3-MetricsQL站在PromQL肩膀上.md"

echo "=== 1. stages 目录 ==="
ls "$BASE/stages/"

echo
echo "=== 2. 学习档案中的课 3 进度 ==="
grep "课 3" "$BASE/00-学习档案.md"

echo
echo "=== 3. 课 3 结构完整性 ==="
for k in '第一幕' '第二幕' '第三幕' '第四幕' '第五幕' \
         '下一批接力提示词' '课程导航' '常见误区' '课后小测' '一图总结' \
         '直觉建立' '核心原理' '示例演示' '一句话记住'; do
  grep -q "$k" "$L3" && printf '   OK    %s\n' "$k" || printf '   MISS  %s\n' "$k"
done

echo
echo "=== 4. 阶段 2 导航链接校验 ==="
grep -oE '\]\(([^)]+\.md)\)' "$L3" | sed 's/](//;s/)//' | sort -u | while read -r link; do
  target="$(dirname "$L3")/$link"
  if [ -f "$target" ]; then printf '   OK      %s\n' "$link"
  else printf '   BROKEN  %s\n' "$link"; fi
done

echo
echo "=== 5. 跨阶段链接（从阶段2 回指阶段1）==="
grep -oE '\]\(\.\./1-[^)]+\.md\)' "$L3" | sed 's/](\.\.\///;s/)//' | while read -r rel; do
  target="$BASE/stages/$rel"
  if [ -f "$target" ]; then printf '   OK      %s\n' "$rel"
  else printf '   BROKEN  %s\n' "$rel"; fi
done

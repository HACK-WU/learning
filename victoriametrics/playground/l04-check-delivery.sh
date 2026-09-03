#!/usr/bin/env bash
# 课 4 交付校验：结构完整性、导航链接、档案同步
set -u
BASE="/mnt/d/projects/learning/victoriametrics"
L4="$BASE/stages/2-数据怎么进来怎么查/4-写入协议全家桶与基数治理.md"

echo "=== 1. 课 4 结构完整性 ==="
for k in '第一幕' '第二幕' '第三幕' '第四幕' '第五幕' \
         '下一批接力提示词' '课程导航' '常见误区' '课后小测' '一图总结' \
         '直觉建立' '核心原理' '示例演示' '一句话记住'; do
  n=$(grep -c "$k" "$L4" 2>/dev/null || echo 0)
  if [ "$n" -gt 0 ]; then printf '   OK    %s (%s次)\n' "$k" "$n"
  else printf '   MISS  %s\n' "$k"; fi
done

echo
echo "=== 2. 阶段内导航链接校验 ==="
grep -oE '\]\(([^)#]+\.md)\)' "$L4" | sed 's/](//;s/)//' | sort -u | while read -r link; do
  target="$(dirname "$L4")/$link"
  if [ -f "$target" ]; then printf '   OK      %s\n' "$link"
  else printf '   BROKEN  %s\n' "$link"; fi
done

echo
echo "=== 3. 上级索引链接校验（../../）==="
grep -oE '\]\(\.\./\.\./[^)#]+\.md\)' "$L4" | sed 's/](\.\.\/\.\.\///;s/)//' | sort -u | while read -r rel; do
  target="$BASE/$rel"
  if [ -f "$target" ]; then printf '   OK      %s\n' "$rel"
  else printf '   BROKEN  %s\n' "$rel"; fi
done

echo
echo "=== 4. 学习档案中的课 4 进度 ==="
grep "课 4" "$BASE/00-学习档案.md"

echo
echo "=== 5. 课程目录中的课 4 ==="
grep -A3 "课 4" "$BASE/02-课程目录.md" | head -6

echo
echo "=== 6. 阶段概览中的课 4 ==="
grep "课 4" "$BASE/stages/2-数据怎么进来怎么查/README.md"

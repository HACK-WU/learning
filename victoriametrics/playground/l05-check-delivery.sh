#!/usr/bin/env bash
# 课 5 交付校验：结构完整性 + 导航链接可达性 + 档案同步
set -u
BASE="/mnt/d/projects/learning/victoriametrics"
L5="$BASE/stages/3-凭什么快凭什么省/5-存储引擎MergeSet与磁盘结构.md"

echo "=== 1. 课 5 结构完整性 ==="
miss=0
for k in '第一幕' '第二幕' '第三幕' '第四幕' '第五幕' \
         '下一批接力提示词' '课程导航' '常见误区' '课后小测' '一图总结' \
         '直觉建立' '核心原理' '示例演示' '一句话记住'; do
  n=$(grep -c "$k" "$L5" 2>/dev/null || echo 0)
  if [ "$n" -gt 0 ]; then printf '   OK    %s (%s次)\n' "$k" "$n"
  else printf '   MISS  %s\n' "$k"; miss=1; fi
done
[ "$miss" = "0" ] && echo "   → 结构 14/14 齐全" || echo "   → 有缺失！"

echo
echo "=== 2. 同目录导航链接校验 ==="
grep -oE '\]\(([^)#]+\.md)\)' "$L5" | sed 's/](//;s/)//' | sort -u | while read -r link; do
  target="$(dirname "$L5")/$link"
  [ -f "$target" ] && printf '   OK      %s\n' "$link" || printf '   BROKEN  %s\n' "$link"
done

echo
echo "=== 3. 跨阶段链接校验（../../2-...）==="
grep -oE '\]\(\.\./\.\./[^)#]+\.md\)' "$L5" | sed 's/](\.\.\/\.\.\///;s/)//' | sort -u | while read -r rel; do
  target="$BASE/$rel"
  [ -f "$target" ] && printf '   OK      %s\n' "$rel" || printf '   BROKEN  %s\n' "$rel"
done

echo
echo "=== 4. 上级索引链接校验（../../02- / ../../01-）==="
grep -oE '\]\(\.\./\.\./(0[12])[^)#]*\.md\)' "$L5" | sed 's/](\.\.\/\.\.\///;s/)//' | sort -u | while read -r rel; do
  target="$BASE/$rel"
  [ -f "$target" ] && printf '   OK      %s\n' "$rel" || printf '   BROKEN  %s\n' "$rel"
done

echo
echo "=== 5. 学习档案中的课 5 ==="
grep "课 5" "$BASE/00-学习档案.md" | grep -E "知识点|未开始|已完成" | head -5

echo
echo "=== 6. 课程目录中的课 5 ==="
grep -A4 "^## 阶段 3" "$BASE/02-课程目录.md" | head -6

echo
echo "=== 7. 阶段概览中的课 5 ==="
grep "课 5" "$BASE/stages/3-凭什么快凭什么省/README.md"

echo
echo "=== 8. 实验脚本是否齐全 ==="
ls "$BASE/playground/" | grep "^l05-" | sed 's/^/   /'

#!/usr/bin/env bash
# 目录化之后的全量链接可达性检查（覆盖场景库 8 文件 + 应用实战 7 篇 + 两个 INDEX）
set -u
BASE=/mnt/d/projects/learning/celery-django
cd "$BASE" || exit 1

check_dir() {
  local dir=$1
  for f in "$dir"/*.md; do
    d=$(dirname "$f")
    grep -oE '\]\(([^)#]+)(#[^)]*)?\)' "$f" | sed 's/](\(.*\))/\1/' | sed 's/#.*//' | sort -u | while read -r link; do
      [ -z "$link" ] && continue
      case "$link" in
        http*|mailto:*) continue ;;
      esac
      if [ -e "$d/$link" ]; then
        echo "  ✅ $(basename "$f") → $link"
      else
        echo "  ❌ $(basename "$f") → $link   (不存在)"
      fi
    done
  done
}

echo "############ 10-场景解法库 ############"
check_dir "10-场景解法库"

echo
echo "############ 应用实战 ############"
check_dir "应用实战"

echo
echo "############ 反向：还有谁指向已删除的 10-场景解法库.md ############"
grep -rn '10-场景解法库\.md' --include='*.md' --include='*.sh' . 2>/dev/null || echo "  ✅ 无残留引用"

echo
echo "############ 图片资源存在性 ############"
for img in $(grep -rhoE '\]\(\./assets/[^)]+\)' 应用实战/*.md 10-场景解法库/*.md | sed 's/](\.\(.*\))/\1/' | sort -u); do
  for base in 应用实战 10-场景解法库; do
    if [ -e "$base/$img" ]; then echo "  ✅ $base$img"; fi
  done
done

echo
echo "############ 孤儿资源（存在但没被引用）############"
for f in 应用实战/assets/*.svg; do
  n=$(basename "$f")
  if ! grep -rq "$n" 应用实战/*.md 2>/dev/null; then echo "  ⚠ 应用实战/assets/$n 未被引用"; fi
done
for f in 10-场景解法库/assets/*.svg; do
  n=$(basename "$f")
  if ! grep -rq "$n" 10-场景解法库/*.md 2>/dev/null; then echo "  ⚠ 10-场景解法库/assets/$n 未被引用"; fi
done
echo "  （无输出 = 全部被引用）"

exit 0

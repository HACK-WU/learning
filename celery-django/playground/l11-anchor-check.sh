#!/usr/bin/env bash
# 单独验证 09 的锚点（上次检查脚本的判断逻辑有缺陷，重做）
set -u
cd /mnt/d/projects/learning/celery-django || exit 1

echo "=== 索引表里所有锚点链接 ==="
grep -oE '\(#[^)]+\)' 09-排障速查手册.md | sort -u

echo
echo "=== 按 GitHub 规则从标题生成实际锚点 ==="
echo "规则：小写、空格→-、去掉 · 和标点、保留中文"
grep -E '^## [0-9]+ · ' 09-排障速查手册.md | while IFS= read -r line; do
  title=$(echo "$line" | sed 's/^## //')
  # GitHub: 小写化 → 空格转 - → 删除非字母数字/中文/-/_ 的字符
  anchor=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[·()（）.,，、]//g')
  echo "  标题: $title"
  echo "  锚点: #$anchor"
done

exit 0

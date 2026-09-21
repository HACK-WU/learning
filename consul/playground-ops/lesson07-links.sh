#!/usr/bin/env bash
B=/mnt/d/projects/learning/consul/子教程/运维专项/lessons
L7="$B/lesson-07-版本升级与迁移.md"
echo "===== 基于 lessons 目录核实真实断链 ====="
BAD=0; TOT=0
while IFS= read -r link; do
  TOT=$((TOT+1))
  tgt="$B/${link%%#*}"
  if [ -f "$tgt" ]; then
    echo "  ✅ $link"
  else
    echo "  ❌ $link  (解析为 $tgt)"
    BAD=$((BAD+1))
  fi
done < <(grep -oE '\]\(([^)]+\.md)\)' "$L7" | sed 's/](\(.*\))/\1/')
echo "  共 $TOT 条，真实断链 $BAD 条"

#!/usr/bin/env bash
# 逐条校验相对链接是否存在
M="/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-01-生产部署与集群搭建.md"
D=$(dirname "$M")
echo "base dir: $D"
echo
grep -oE '\]\(\.\.?[^)]+\)' "$M" | sed 's/^](//;s/)$//' | sort -u | while read -r rel; do
  target="$D/$rel"
  if [ -e "$target" ]; then
    printf "  OK    %s\n" "$rel"
  else
    printf "  DEAD  %s\n" "$rel"
  fi
done

#!/usr/bin/env bash
# 结构复检（修复版）：同时校验课文件的五幕、必备段与导航链接可达性
set -u
BASE="/mnt/d/projects/learning/victoriametrics"
DIR="$BASE/stages/1-为什么需要VictoriaMetrics"

check_file() {
  local f="$1"
  echo "=== $(basename "$f") ==="
  local key miss=0
  for key in '第一幕' '第二幕' '第三幕' '第四幕' '第五幕' \
             '下一批接力提示词' '课程导航' '常见误区' '课后小测' '一图总结' \
             '直觉建立' '核心原理' '示例演示' '一句话记住'; do
    if grep -q "$key" "$f"; then
      printf '   OK    %s\n' "$key"
    else
      printf '   MISS  %s\n' "$key"
      miss=$((miss + 1))
    fi
  done
  echo "   ---- 缺失项: ${miss} ----"
  echo "   ---- 导航链接校验 ----"
  grep -oE '\]\(([^)]+\.md)\)' "$f" | sed 's/](//;s/)//' | sort -u | while read -r link; do
    local target="$DIR/$link"
    if [ -f "$target" ]; then
      printf '   OK    %s\n' "$link"
    else
      printf '   BROKEN %s\n' "$link"
    fi
  done
}

for f in "$DIR"/1-*.md "$DIR"/2-*.md; do
  [ -f "$f" ] && check_file "$f"
done

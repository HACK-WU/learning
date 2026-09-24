#!/bin/bash
# 复审 P0 修复：表A/表B 加速比 5 次采样取范围
# 触发：复审实测与讲义偏差 82%，同为「单点值当结论」
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
echo "表A(CPU密集) / 表B(CPU+IO) 加速比 5 次采样"
echo "=================================================================="
printf "%-6s %-10s %-10s %-10s %-10s %-10s\n" \
  "次数" "A线程x4" "A进程x4" "B线程x4" "B进程x4"
echo "------------------------------------------------------------------"
for i in 1 2 3 4 5; do
  out=$(bash "$B/l10_models.sh" 2>&1)
  at=$(echo "$out" | sed -n '/A. CPU/,/B. CPU/p' | grep '线程 x4' | grep -oE '[0-9.]+x' | tail -1)
  ap=$(echo "$out" | sed -n '/A. CPU/,/B. CPU/p' | grep '进程 x4' | grep -oE '[0-9.]+x' | tail -1)
  bt=$(echo "$out" | sed -n '/B. CPU/,$p' | grep '线程 x4' | grep -oE '[0-9.]+x' | tail -1)
  bp=$(echo "$out" | sed -n '/B. CPU/,$p' | grep '进程 x4' | grep -oE '[0-9.]+x' | tail -1)
  printf "%-6s %-10s %-10s %-10s %-10s\n" "$i" "$at" "$ap" "$bt" "$bp"
done
echo "=================================================================="
echo "判定：以区间呈现；重点关注区间是否重叠（决定结论是否稳定）"

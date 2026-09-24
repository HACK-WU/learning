#!/bin/bash
# 复审 P0 修复：chunksize=1 到底是 0.71x 还是 1.74x？方向性矛盾必须定论
# 5 次采样，看区间是否重叠
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
echo "chunksize=1 vs chunksize=50，各 5 次采样"
echo "=================================================="
printf "%-6s %-18s %-18s\n" "次数" "cs=1 加速比" "cs=50 加速比"
echo "--------------------------------------------------"
for i in 1 2 3 4 5; do
  out=$(bash "$B/l10_diag_chunksize2.sh" 2>&1)
  a=$(echo "$out" | grep 'chunksize=1 ' | grep -oE '[0-9.]+x' | head -1)
  b=$(echo "$out" | grep 'chunksize=50 ' | grep -oE '[0-9.]+x' | head -1)
  printf "%-6s %-18s %-18s\n" "$i" "$a" "$b"
done
echo "=================================================="
echo "判定：若 cs=1 区间与 cs=50 区间重叠 -> 结论『chunksize 影响不大』"
echo "      若 cs=1 恒低于 cs=50 且不重叠 -> 结论『chunksize 确有影响』"

#!/bin/bash
# 复审 P0 修复：Protobuf 章节吞吐 5 次采样取范围
# 触发：复审实测 Avro 633,789 vs 讲义 780,501，差 19%
# 同一类问题在第二节已修过一次（JSON/Avro），Protobuf 章节又犯了
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
echo "三方吞吐 5 次采样 (N=20000)"
echo "--------------------------------------------------------------"
printf "%-6s %-14s %-14s %-14s\n" "次数" "JSON" "Avro" "Protobuf"
echo "--------------------------------------------------------------"
for i in 1 2 3 4 5; do
  out=$(bash "$B/l9_protobuf.sh" 2>&1 | grep -E '^    (JSON|Avro|Protobuf) +[0-9,]+ +[0-9,]+')
  j=$(echo "$out" | grep '^    JSON'     | grep -oE '[0-9,]+/s|[0-9,]+ ' | head -1 | tr -d ' ,')
  a=$(echo "$out" | grep '^    Avro'     | grep -oE '[0-9,]+ ' | head -1 | tr -d ' ,')
  p=$(echo "$out" | grep '^    Protobuf' | grep -oE '[0-9,]+ ' | head -1 | tr -d ' ,')
  # 只取吞吐表（该行有 3 个数字且第2个 >= 100000）
  j=$(echo "$out" | awk '/^    JSON/     {gsub(/,/,"",$2); if ($2+0>100000) print $2}')
  a=$(echo "$out" | awk '/^    Avro/     {gsub(/,/,"",$2); if ($2+0>100000) print $2}')
  p=$(echo "$out" | awk '/^    Protobuf/ {gsub(/,/,"",$2); if ($2+0>100000) print $2}')
  printf "%-6s %-14s %-14s %-14s\n" "$i" "$j" "$a" "$p"
done
echo "--------------------------------------------------------------"
echo "判定：以最小值和最大值构成区间，讲义不得写死单点值"

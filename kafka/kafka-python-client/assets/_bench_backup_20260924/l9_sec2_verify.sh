#!/bin/bash
# 复审疑点：第 2 节写 Avro 490,367~529,664，但 Protobuf 章节的 Avro 跑到 798,640
# 两个脚本用的是不同实现（l9_format_compare vs l9_protobuf），需确认第 2 节区间是否仍成立
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
echo "l9_format_compare.sh（第 2 节数据源）5 次采样"
echo "----------------------------------------------"
printf "%-6s %-16s %-16s\n" "次数" "JSON编码/s" "Avro编码/s"
echo "----------------------------------------------"
for i in 1 2 3 4 5; do
  out=$(bash "$B/l9_format_compare.sh" 2>&1 | grep -E '^JSON +[0-9]|^Avro \(fastavro')
  j=$(echo "$out" | grep '^JSON' | grep -oE '[0-9,]+/s' | head -1 | tr -d ',/s')
  a=$(echo "$out" | grep '^Avro' | grep -oE '[0-9,]+/s' | head -1 | tr -d ',/s')
  printf "%-6s %-16s %-16s\n" "$i" "$j" "$a"
done
echo "----------------------------------------------"
echo "若本区间与第2节所写 420,013~443,395 / 490,367~529,664 明显不符 -> 需修正讲义"

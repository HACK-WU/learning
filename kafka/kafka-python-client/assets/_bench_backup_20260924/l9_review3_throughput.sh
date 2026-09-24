#!/bin/bash
# 复审 P0 复核：吞吐量数值是否稳定
# 触发：首轮 504354，复审 489553 —— 差 3%，且 JSON 也涨了
# 按「数值浮动如实说明」纪律：跑 5 次取范围，不许拿单次采样当结论
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
echo "吞吐量 5 次采样（每次 N=20000）"
echo "-----------------------------------------"
printf "%-6s %-16s %-16s %s\n" "次数" "JSON编码/s" "Avro编码/s" "谁快"
echo "-----------------------------------------"
for i in 1 2 3 4 5; do
  out=$(bash "$B/l9_format_compare.sh" 2>&1 | grep -E '^JSON +[0-9]|^Avro \(fastavro')
  # 用 grep -o 抓 "数字,/s" 的第一个，避免中文列宽导致 awk 列偏移
  j=$(echo "$out" | grep '^JSON' | grep -oE '[0-9,]+/s' | head -1 | tr -d ',/s')
  a=$(echo "$out" | grep '^Avro' | grep -oE '[0-9,]+/s' | head -1 | tr -d ',/s')
  if [ -n "$j" ] && [ -n "$a" ]; then
    if [ "$a" -gt "$j" ]; then w="Avro"; else w="JSON"; fi
    printf "%-6s %-16s %-16s %s\n" "$i" "$j" "$a" "$w"
  else
    printf "%-6s %s\n" "$i" "解析失败: $out"
  fi
done
echo "-----------------------------------------"
echo "判定：若 5 次中 Avro 与 JSON 互有胜负 -> 两者性能【同一量级】，"
echo "      讲义不能写死'Avro 更快'，应写'两者同量级，性能不是选型依据'"

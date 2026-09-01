#!/bin/bash
# 用官方 redis-benchmark 重测 io-threads（修正 \r 进度条干扰）

bench() {
  local port=$1 bth=$2 conns=$3 pipe=$4 size=$5
  local out
  out=$(redis-benchmark -h 127.0.0.1 -p $port -n 500000 -c $conns -P $pipe -d $size \
        --threads $bth -t get,set -q 2>/dev/null | tr '\r' '\n')
  local g=$(echo "$out" | grep -oE "^GET: [0-9]+\.[0-9]+" | grep -oE "[0-9]+\.[0-9]+" | tail -1)
  local s=$(echo "$out" | grep -oE "^SET: [0-9]+\.[0-9]+" | grep -oE "[0-9]+\.[0-9]+" | tail -1)
  echo "${g:-NA}|${s:-NA}"
}

echo "================================================================"
echo "  实验 4b：io-threads 实测（官方 redis-benchmark，C 客户端）"
echo "  Redis 8.10.1 / 20 核 / 回环网络(lo)"
echo "================================================================"

for size in 3 1024 10240; do
  echo ""
  echo "----------------------------------------------------------------"
  echo "  value = ${size} B    (各跑 50 万次请求)"
  echo "----------------------------------------------------------------"
  printf "%-12s | %-16s | %-16s | %-16s\n" \
         "io-threads" "50并发 GET" "50并发 SET" "200并发 GET"
  printf "%s\n" "--------------------------------------------------------------------------"
  for spec in "7102:1" "7103:4" "7104:8"; do
    port=${spec%%:*}; t=${spec##*:}
    r1=$(bench $port $t 50 1 $size)
    g1=$(echo $r1 | cut -d'|' -f1); s1=$(echo $r1 | cut -d'|' -f2)
    r2=$(bench $port $t 200 1 $size)
    g2=$(echo $r2 | cut -d'|' -f1)
    printf "io-th=%-2s      | %-16s | %-16s | %-16s\n" "$t" "$g1" "$s1" "$g2"
  done
done

echo ""
echo "================================================================"
echo "  pipeline 场景（-P 16），200 并发，value=1024B"
echo "================================================================"
printf "%-12s | %-18s | %-18s\n" "io-threads" "GET" "SET"
printf "%s\n" "------------------------------------------------------------"
for spec in "7102:1" "7103:4" "7104:8"; do
  port=${spec%%:*}; t=${spec##*:}
  r=$(bench $port $t 200 16 1024)
  g=$(echo $r | cut -d'|' -f1); s=$(echo $r | cut -d'|' -f2)
  printf "io-th=%-2s      | %-18s | %-18s\n" "$t" "$g" "$s"
done

echo ""
echo "================================================================"
echo "  代价：CPU 用量（压测后累计值）"
echo "================================================================"
for spec in "7102:1" "7103:4" "7104:8"; do
  port=${spec%%:*}; t=${spec##*:}
  sys=$(redis-cli -p $port info cpu 2>/dev/null | grep "used_cpu_sys:" | cut -d: -f2)
  main=$(redis-cli -p $port info cpu 2>/dev/null | grep "used_cpu_main:" | cut -d: -f2)
  echo "  io-threads=$t : used_cpu_sys=${sys}  used_cpu_main=${main:-N/A}"
done

echo ""
echo "================================================================"
echo "  io 线程是否真的在工作（累计处理数）"
echo "================================================================"
for spec in "7102:1" "7103:4" "7104:8"; do
  port=${spec%%:*}; t=${spec##*:}
  echo -n "  io-threads=$t : "
  redis-cli -p $port info stats 2>/dev/null | grep -E "io_threaded_(reads|writes)_processed" | tr '\n' ' '
  echo ""
done

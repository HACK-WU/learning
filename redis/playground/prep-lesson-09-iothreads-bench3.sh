#!/bin/bash
# 用官方 redis-benchmark 重测 io-threads，排除 Python 客户端瓶颈
# 官方文档明确：benchmark 本身要用 --threads 匹配服务端线程数

echo "================================================================"
echo "  实验 4b：用官方 redis-benchmark 重测 io-threads"
echo "  Redis 8.10.1 / 20 核 / 回环网络"
echo "================================================================"

run_bench() {
  local port=$1
  local t=$2
  local conns=$3
  local pipe=$4
  local size=$5
  local bthreads=$6

  local out
  out=$(redis-benchmark -h 127.0.0.1 -p $port \
        -n 500000 -c $conns -P $pipe -d $size \
        --threads $bthreads -t get,set -q 2>/dev/null)
  local get_qps=$(echo "$out" | grep -i "^GET:" | grep -oE "[0-9]+\.[0-9]+" | head -1)
  local set_qps=$(echo "$out" | grep -i "^SET:" | grep -oE "[0-9]+\.[0-9]+" | head -1)
  echo "$get_qps|$set_qps"
}

for size in 3 1024; do
  echo ""
  echo "================================================================"
  echo "  value 大小 = ${size} B"
  echo "================================================================"
  printf "%-8s %-6s | %14s %14s | %14s %14s\n" \
         "服务端" "客户端" "GET(50并发)" "SET(50并发)" "GET(200并发)" "SET(200并发)"
  printf "%s\n" "----------------------------------------------------------------"

  for spec in "7102:1" "7103:4" "7104:8"; do
    port=${spec%%:*}
    t=${spec##*:}
    # benchmark 客户端线程数 = 1（不匹配）
    r1=$(run_bench $port $t 50 1 $size 1)
    g1=$(echo $r1 | cut -d'|' -f1); s1=$(echo $r1 | cut -d'|' -f2)
    # benchmark 客户端线程数 = 与服务端 io-threads 一致（官方推荐做法）
    r2=$(run_bench $port $t 200 1 $size $t)
    g2=$(echo $r2 | cut -d'|' -f1); s2=$(echo $r2 | cut -d'|' -f2)
    printf "io-th=%-2s  %-6s | %14s %14s | %14s %14s\n" \
           "$t" "1/$t" "$g1" "$s1" "$g2" "$s2"
  done
done

echo ""
echo "================================================================"
echo "  pipeline 场景（-P 16），200 并发"
echo "================================================================"
printf "%-10s | %16s %16s\n" "服务端" "GET" "SET"
printf "%s\n" "------------------------------------------------"
for spec in "7102:1" "7103:4" "7104:8"; do
  port=${spec%%:*}
  t=${spec##*:}
  out=$(redis-benchmark -h 127.0.0.1 -p $port -n 1000000 -c 200 -P 16 \
        --threads $t -t get,set -q 2>/dev/null)
  g=$(echo "$out" | grep -i "^GET:" | grep -oE "[0-9]+\.[0-9]+" | head -1)
  s=$(echo "$out" | grep -i "^SET:" | grep -oE "[0-9]+\.[0-9]+" | head -1)
  printf "io-th=%-2s   | %16s %16s\n" "$t" "$g" "$s"
done

echo ""
echo "================================================================"
echo "  压测后 io 线程激活计数"
echo "================================================================"
for spec in "7102:1" "7103:4" "7104:8"; do
  port=${spec%%:*}
  t=${spec##*:}
  echo -n "  io-threads=$t : "
  redis-cli -p $port info stats 2>/dev/null | grep -E "io_threaded_(reads|writes)_processed" | tr '\n' ' '
  echo ""
done

echo ""
echo "================================================================"
echo "  CPU 用量对比（used_cpu_main / used_cpu_sys）"
echo "================================================================"
for spec in "7102:1" "7103:4" "7104:8"; do
  port=${spec%%:*}
  t=${spec##*:}
  echo -n "  io-threads=$t : "
  redis-cli -p $port info cpu 2>/dev/null | grep -E "used_cpu_main:|used_cpu_sys:" | tr '\n' ' '
  echo ""
done

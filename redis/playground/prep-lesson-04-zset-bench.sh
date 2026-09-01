#!/usr/bin/env bash
# 课 4 知识点 2 修正：用 redis-benchmark 隔离进程开销，测真实命令耗时
# 关键：redis-cli 每次启动约 1.5ms 固定开销，会淹没命令本身耗时
PORT=6404
DIR=/tmp/redis-course-l04b3
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "=== 先量化 redis-cli 的进程启动开销（基线）==="
s=$(date +%s%N)
for i in $(seq 1 200); do redis-cli -p "$PORT" ping > /dev/null; done
e=$(date +%s%N)
base_ms=$(awk "BEGIN{printf \"%.4f\", ($e-$s)/200/1000000}")
echo "单次 redis-cli 往返 PING 耗时: ${base_ms} ms  <-- 这是进程开销基线，所有命令都含它"

echo ""
echo "=== 用 redis-benchmark 测真实命令吞吐（单进程内，无启动开销）==="
echo ""

printf "%-10s %-16s %-16s %-16s\n" "规模" "ZSCORE" "ZREVRANK" "LINDEX"
printf "%-10s %-16s %-16s %-16s\n" "----------" "----------------" "----------------" "----------------"

for n in 10000 100000 1000000; do
  zkey="z:b:$n"
  lkey="l:b:$n"
  redis-cli -p "$PORT" del "$zkey" "$lkey" > /dev/null
  seq 1 "$n" | awk -v k="$zkey" '{print "zadd "k" "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  seq 1 "$n" | sed "s/^/v/" | awk -v k="$lkey" '{print "rpush "k" "$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  mid=$((n/2))

  # ZSCORE：随机 key 用 __rand_int__ 不适用，改为固定 member 但用 -r 无意义，直接测固定 member
  zs=$(redis-benchmark -p "$PORT" -n 20000 -c 1 zscore "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  zr=$(redis-benchmark -p "$PORT" -n 20000 -c 1 zrevrank "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  li=$(redis-benchmark -p "$PORT" -n 5000 -c 1 lindex "$lkey" "$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')

  printf "%-10s %-16s %-16s %-16s\n" "$n" "${zs} ops/s" "${zr} ops/s" "${li} ops/s"
done

echo ""
echo "=== 换算成单次耗时（微妙 us）==="
echo "公式：单次耗时(us) = 1000000 / ops_per_second"
printf "%-10s %-16s %-16s %-16s\n" "规模" "ZSCORE(us)" "ZREVRANK(us)" "LINDEX(us)"
printf "%-10s %-16s %-16s %-16s\n" "----------" "----------------" "----------------" "----------------"
for n in 10000 100000 1000000; do
  zkey="z:b:$n"; lkey="l:b:$n"; mid=$((n/2))
  zs=$(redis-benchmark -p "$PORT" -n 20000 -c 1 zscore "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  zr=$(redis-benchmark -p "$PORT" -n 20000 -c 1 zrevrank "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  li=$(redis-benchmark -p "$PORT" -n 5000 -c 1 lindex "$lkey" "$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  printf "%-10s %-16s %-16s %-16s\n" "$n" \
    "$(awk "BEGIN{printf \"%.3f\", 1000000/$zs}")" \
    "$(awk "BEGIN{printf \"%.3f\", 1000000/$zr}")" \
    "$(awk "BEGIN{printf \"%.3f\", 1000000/$li}")"
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"

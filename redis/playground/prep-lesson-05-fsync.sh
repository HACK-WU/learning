#!/usr/bin/env bash
# 课 5 AOF 刷盘策略修正版：多轮取中位数，消除测试噪声
# 问题：单轮 benchmark 波动大，曾出现 everysec 比 no 还快的反常结果
PORT=6405
DIR=/tmp/redis-course-l05-fsync
rm -rf "$DIR"; mkdir -p "$DIR"

redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1.5
echo "appendonly=$(redis-cli -p "$PORT" config get appendonly | tail -1)"
echo ""

echo "=== 三轮取中位数，每轮 10 万次 SET ==="
echo ""

median() {
  # $1..$n 数字，输出中位数
  printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END{ if(NR%2) print a[(NR+1)/2]; else printf "%.2f", (a[NR/2]+a[NR/2+1])/2 }'
}

printf "%-12s %-16s %-16s %-16s %-14s\n" "策略" "第1轮" "第2轮" "第3轮" "中位数"
printf "%-12s %-16s %-16s %-16s %-14s\n" "------------" "----------------" "----------------" "----------------" "--------------"

declare -A MED
for pol in no everysec always; do
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  sleep 1
  r1=$(redis-benchmark -p "$PORT" -n 100000 -c 10 -t set -q 2>/dev/null | grep -oP 'SET: \K[\d.]+')
  sleep 0.5
  r2=$(redis-benchmark -p "$PORT" -n 100000 -c 10 -t set -q 2>/dev/null | grep -oP 'SET: \K[\d.]+')
  sleep 0.5
  r3=$(redis-benchmark -p "$PORT" -n 100000 -c 10 -t set -q 2>/dev/null | grep -oP 'SET: \K[\d.]+')
  [ -z "$r1" ] && r1=0; [ -z "$r2" ] && r2=0; [ -z "$r3" ] && r3=0
  M=$(median "$r1" "$r2" "$r3")
  MED[$pol]=$M
  printf "%-12s %-16s %-16s %-16s %-14s\n" "$pol" "$r1" "$r2" "$r3" "$M"
done

echo ""
echo "=== 以 no 为基准的归一化 ==="
B=${MED[no]}
for pol in no everysec always; do
  printf "%-12s %-18s %-14s\n" "$pol" "${MED[$pol]} ops/s" \
    "$(awk -v t=${MED[$pol]} -v b=$B 'BEGIN{printf "%.3fx", t/b}')"
done

echo ""
echo "=== 延迟分布（P50/P95/P99，单位 ms）==="
printf "%-12s %-14s %-14s %-14s\n" "策略" "P50" "P95" "P99"
printf "%-12s %-14s %-14s %-14s\n" "------------" "--------------" "--------------" "--------------"
for pol in no everysec always; do
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  sleep 1
  OUT=$(redis-benchmark -p "$PORT" -n 50000 -c 10 -t set 2>/dev/null)
  P50=$(echo "$OUT" | grep -oP '(?<=^50% <= )[\d.]+(?= milliseconds)' | head -1)
  P95=$(echo "$OUT" | grep -oP '(?<=^95% <= )[\d.]+(?= milliseconds)' | head -1)
  P99=$(echo "$OUT" | grep -oP '(?<=^99% <= )[\d.]+(?= milliseconds)' | head -1)
  [ -z "$P50" ] && P50="-"
  [ -z "$P95" ] && P95="-"
  [ -z "$P99" ] && P99="-"
  printf "%-12s %-14s %-14s %-14s\n" "$pol" "$P50 ms" "$P95 ms" "$P99 ms"
done

echo ""
echo "=== 关键：aof_delayed_fsync 计数器（everysec 下后台 fsync 是否滞后）==="
redis-cli -p "$PORT" config set appendfsync everysec > /dev/null
for i in $(seq 1 20000); do echo "set dk:$i v$i"; done | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 1
echo "  $(redis-cli -p "$PORT" info persistence | grep -E 'aof_delayed_fsync|aof_pending_bio_fsync' | tr '\n' ' ')"
echo "  aof_rewrite_in_progress: $(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^aof_rewrite_in_progress:)\d+')"

echo ""
echo "=== 恢复默认 ==="
redis-cli -p "$PORT" config set appendfsync everysec > /dev/null

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -rf "$DIR"
echo "done"

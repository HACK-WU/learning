#!/usr/bin/env bash
# 课 3 备课脚本 G：进程内大批量计时，剥离网络往返，测出 LINDEX 的真实成本
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-03-lindex.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l03g
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

echo "########## 进程内计时：1 次 eval 里执行 100000 次 LINDEX ##########"
echo "（剥离网络往返，只测 Redis 内部成本；每次 eval 的耗时用客户端粗略计时，量级差异足够明显）"
echo ""
echo "| 元素数 | 100000 次 LINDEX(中间) 总耗时 | 单次均值 |"
echo "|--------|---------------------------|---------|"

for N in 10000 1000000 5000000; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','t',string.rep('v',20)..i) end return 'ok'" 0 "$N"
  MID=$((N/2))
  S=$(date +%s%N)
  redis-cli -p "$PORT" eval "
    for i=1,100000 do redis.call('lindex','t',tonumber(ARGV[1])) end
    return 'done'" 0 "$MID" > /dev/null
  E=$(date +%s%N)
  MS=$(( (E - S) / 1000000 ))
  echo "| $N | ${MS} ms | $(awk -v m="$MS" 'BEGIN{printf "%.4f", m/100000}') ms |"
done

echo ""
echo "########## 对照：1 次 eval 里执行 100000 次 LPOP（O(1)）##########"
echo "| 元素数 | 100000 次 LPOP 总耗时 | 单次均值 |"
echo "|--------|---------------------|---------|"
for N in 10000 5000000; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','t',string.rep('v',20)..i) end return 'ok'" 0 "$N"
  S=$(date +%s%N)
  redis-cli -p "$PORT" eval "
    for i=1,100000 do redis.call('lpop','t') end
    return 'done'" 0 > /dev/null
  E=$(date +%s%N)
  MS=$(( (E - S) / 1000000 ))
  echo "| $N | ${MS} ms | $(awk -v m="$MS" 'BEGIN{printf "%.4f", m/100000}') ms |"
done

echo ""
echo "########## 大 List 的真实代价：内存 ##########"
for N in 100000 1000000 5000000; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','t',string.rep('v',20)..i) end return 'ok'" 0 "$N"
  MEM=$(redis-cli -p "$PORT" memory usage t)
  echo "N=$N → List 占用 $((MEM/1024)) KB（约 $(awk -v m="$MEM" 'BEGIN{printf "%.1f", m/1024/1024}') MB）"
done

echo ""
echo "########## 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"

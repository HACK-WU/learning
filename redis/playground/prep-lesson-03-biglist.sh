#!/usr/bin/env bash
# 课 3 备课脚本 D：用 --latency 采样，测量大 List 操作期间对其他命令的阻塞
# 原因：LRANGE/LINDEX 自身耗时太短（<10ms）测不出，但它们占用主线程的时间会体现在其他命令的延迟上
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-03-biglist.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l03d
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

N=5000000
echo "########## 造 $N 个元素的 List（约需 30-60 秒）##########"
redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','bigq','value'..i) end return 'ok'" 0 "$N"
echo "长度: $(redis-cli -p "$PORT" llen bigq)"
echo "bigq 占用内存: $(redis-cli -p "$PORT" memory usage bigq) 字节"

echo ""
echo "########## 基准：空闲时 PING 最大延迟 ##########"
rm -f /tmp/base.txt
(
  MAX=0
  for i in $(seq 1 100); do
    S=$(date +%s%N); redis-cli -p "$PORT" ping > /dev/null; E=$(date +%s%N)
    MS=$(( (E - S) / 1000000 )); [ "$MS" -gt "$MAX" ] && MAX=$MS
  done
  echo "$MAX" > /tmp/base.txt
) 
echo "空闲基准最大延迟: $(cat /tmp/base.txt) ms"

echo ""
echo "########## 执行 LINDEX bigq <中间下标> 期间，测 PING 最大延迟 ##########"
MID=$((N/2))
S=$(date +%s.%N)
redis-cli -p "$PORT" lindex bigq "$MID" > /dev/null &
LP=$!
MAX=0
while kill -0 $LP 2>/dev/null; do
  S2=$(date +%s%N); redis-cli -p "$PORT" ping > /dev/null 2>&1; E2=$(date +%s%N)
  MS=$(( (E2 - S2) / 1000000 )); [ "$MS" -gt "$MAX" ] && MAX=$MS
done
E=$(date +%s.%N)
wait $LP 2>/dev/null
echo "LINDEX 第 $MID 个元素，自身耗时: $(echo "$E - $S" | bc) 秒"
echo "期间其他命令被阻塞的最大延迟: ${MAX} ms"

echo ""
echo "########## 执行 LRANGE bigq -10 -1 期间，测 PING 最大延迟 ##########"
S=$(date +%s.%N)
redis-cli -p "$PORT" lrange bigq -10 -1 > /dev/null &
LP=$!
MAX2=0
while kill -0 $LP 2>/dev/null; do
  S2=$(date +%s%N); redis-cli -p "$PORT" ping > /dev/null 2>&1; E2=$(date +%s%N)
  MS=$(( (E2 - S2) / 1000000 )); [ "$MS" -gt "$MAX2" ] && MAX2=$MS
done
E=$(date +%s.%N)
wait $LP 2>/dev/null
echo "LRANGE 尾 10 条，自身耗时: $(echo "$E - $S" | bc) 秒"
echo "期间其他命令被阻塞的最大延迟: ${MAX2} ms"

echo ""
echo "########## 对照：LPOP（O(1)）期间，测 PING 最大延迟 ##########"
S=$(date +%s.%N)
redis-cli -p "$PORT" lpop bigq > /dev/null &
LP=$!
MAX3=0
while kill -0 $LP 2>/dev/null; do
  S2=$(date +%s%N); redis-cli -p "$PORT" ping > /dev/null 2>&1; E2=$(date +%s%N)
  MS=$(( (E2 - S2) / 1000000 )); [ "$MS" -gt "$MAX3" ] && MAX3=$MS
done
E=$(date +%s.%N)
wait $LP 2>/dev/null
echo "LPOP 自身耗时: $(echo "$E - $S" | bc) 秒"
echo "期间其他命令被阻塞的最大延迟: ${MAX3} ms"

echo ""
echo "########## 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"

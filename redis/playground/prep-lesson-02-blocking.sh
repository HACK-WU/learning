#!/usr/bin/env bash
# 课 2 备课脚本 B：用真实数据量对比 KEYS 与 SCAN 的"阻塞"差异
# 关键点：KEYS 的危险不在于它自己跑多久，而在于它跑的这段时间里，其他所有命令都在排队
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-02-blocking.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l02b
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

N=1000000
echo "########## 造 $N 个 key（约需十几秒）##########"
redis-cli -p "$PORT" eval "local i=0 while i < tonumber(ARGV[1]) do i = i + 1 redis.call('set', 'biz:item:'..i, string.rep('v', 50)) end return i" 0 "$N"
echo "key 总数:"; redis-cli -p "$PORT" dbsize

echo ""
echo "########## 基准：空闲时 PING 延迟 ##########"
# 后台持续 PING 采样，记录最大延迟
(
  MAX=0
  for i in $(seq 1 200); do
    S=$(date +%s%N)
    redis-cli -p "$PORT" ping > /dev/null
    E=$(date +%s%N)
    MS=$(( (E - S) / 1000000 ))
    if [ "$MS" -gt "$MAX" ]; then MAX=$MS; fi
    sleep 0.005
  done
  echo "IDLE_MAX:$MAX" > /tmp/idle.txt
) &
BG1=$!
sleep 2.5
kill $BG1 2>/dev/null
wait $BG1 2>/dev/null
cat /tmp/idle.txt

echo ""
echo "########## 实验 A：执行 KEYS biz:item:* 期间，测 PING 延迟 ##########"
S=$(date +%s.%N)
redis-cli -p "$PORT" keys "biz:item:*" > /tmp/keys_out.txt &
KEYSPID=$!

MAX=0
while kill -0 $KEYSPID 2>/dev/null; do
  S2=$(date +%s%N)
  redis-cli -p "$PORT" ping > /dev/null 2>&1
  E2=$(date +%s%N)
  MS=$(( (E2 - S2) / 1000000 ))
  if [ "$MS" -gt "$MAX" ]; then MAX=$MS; fi
done
E=$(date +%s.%N)
wait $KEYSPID 2>/dev/null
echo "KEYS 自身耗时: $(echo "$E - $S" | bc) 秒"
echo "KEYS 期间其他命令被阻塞的最大延迟: ${MAX} ms"
echo "KEYS 返回 key 行数: $(wc -l < /tmp/keys_out.txt)"

echo ""
echo "########## 实验 B：执行 SCAN 遍历期间，测 PING 延迟 ##########"
S=$(date +%s.%N)
(
  CURSOR=0
  while true; do
    RESP=$(redis-cli -p "$PORT" scan "$CURSOR" match "biz:item:*" count 1000)
    CURSOR=$(echo "$RESP" | head -1 | tr -d '\r')
    if [ "$CURSOR" = "0" ]; then break; fi
  done
  echo done > /tmp/scan_done.txt
) &
SCANPID=$!

MAX2=0
rm -f /tmp/scan_done.txt
while [ ! -f /tmp/scan_done.txt ]; do
  S2=$(date +%s%N)
  redis-cli -p "$PORT" ping > /dev/null 2>&1
  E2=$(date +%s%N)
  MS=$(( (E2 - S2) / 1000000 ))
  if [ "$MS" -gt "$MAX2" ]; then MAX2=$MS; fi
done
E=$(date +%s.%N)
wait $SCANPID 2>/dev/null
echo "SCAN 自身耗时: $(echo "$E - $S" | bc) 秒"
echo "SCAN 期间其他命令被阻塞的最大延迟: ${MAX2} ms"

echo ""
echo "########## 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 已清理"

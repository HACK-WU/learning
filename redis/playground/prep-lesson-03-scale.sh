#!/usr/bin/env bash
# 课 3 备课脚本 F：用客户端批量计时验证 LINDEX 随规模的增长趋势（修正 Lua 计时精度不足）
# 同时验证 listpack → quicklist 的编码切换点
# 用法：bash /mnt/d/projects/learning/redis/playground/prep-lesson-03-scale.sh

set -u
PORT=6399
DIR=/tmp/redis-course-l03f
mkdir -p "$DIR"
cd "$DIR" || exit 1

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" \
  --enable-debug-command yes > /dev/null 2>&1
sleep 1
redis-cli -p "$PORT" flushall > /dev/null

echo "########## 1. List 编码随规模的切换（listpack → quicklist）##########"
for N in 10 100 1000 5000; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','t','value'..i) end return 'ok'" 0 "$N"
  echo "N=$(redis-cli -p "$PORT" llen t)  →  编码: $(redis-cli -p "$PORT" object encoding t)"
done

echo ""
echo "########## 2. quicklist 节点切分（DEBUG 已开启）##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" eval "for i=1,10000 do redis.call('rpush','bigq','value'..i) end return 'ok'" 0
echo "长度: $(redis-cli -p "$PORT" llen bigq)"
echo "--- DEBUG QUICKLIST-PACKED-INFO ---"
redis-cli -p "$PORT" debug quicklist-packed-info bigq 2>&1 | head -8
echo "--- 节点数（DEBUG OBJECT 或 quicklist-info）---"
redis-cli -p "$PORT" debug quicklist-info bigq 2>&1 | head -8

echo ""
echo "########## 3. LINDEX 随规模增长趋势（客户端计时，每档执行 2000 次取总耗时）##########"
for N in 100000 1000000 3000000; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','t',string.rep('v',20)..i) end return 'ok'" 0 "$N"
  MID=$((N/2))
  S=$(date +%s%N)
  for i in $(seq 1 2000); do
    redis-cli -p "$PORT" lindex t "$MID" > /dev/null
  done
  E=$(date +%s%N)
  MS=$(( (E - S) / 1000000 ))
  echo "N=$N（下标 $MID）: 2000 次 LINDEX 总耗时 ${MS} ms，单次约 $(awk -v m="$MS" 'BEGIN{printf "%.3f", m/2000}') ms"
done

echo ""
echo "########## 4. 对照：LPOP（O(1)）不随规模增长 ##########"
for N in 100000 3000000; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" eval "for i=1,tonumber(ARGV[1]) do redis.call('rpush','t',string.rep('v',20)..i) end return 'ok'" 0 "$N"
  S=$(date +%s%N)
  for i in $(seq 1 2000); do
    redis-cli -p "$PORT" lpop t > /dev/null
  done
  E=$(date +%s%N)
  MS=$(( (E - S) / 1000000 ))
  echo "N=$N: 2000 次 LPOP 总耗时 ${MS} ms，单次约 $(awk -v m="$MS" 'BEGIN{printf "%.3f", m/2000}') ms（含网络往返）"
done

echo ""
echo "########## 5. 清理 ##########"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
echo "OK: 实例已关闭"

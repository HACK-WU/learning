#!/bin/bash
set -u
MOD=/usr/lib/redis/modules
PORT=7101
DIR=/tmp/redis-l09
LOG=$DIR/7101.log

mkdir -p $DIR

# 若已存在则先停
redis-cli -p $PORT shutdown nosave 2>/dev/null
sleep 0.5

nohup redis-server \
  --port $PORT \
  --bind 127.0.0.1 \
  --dir $DIR \
  --daemonize no \
  --save '' \
  --appendonly no \
  --maxmemory 0 \
  --maxmemory-policy noeviction \
  --loadmodule $MOD/redisbloom.so \
  --loadmodule $MOD/rejson.so \
  > $LOG 2>&1 &

for i in $(seq 1 30); do
  if redis-cli -p $PORT ping 2>/dev/null | grep -q PONG; then
    echo "7101 就绪 (${i}00ms)"
    break
  fi
  sleep 0.1
done

redis-cli -p $PORT info server 2>/dev/null | grep -E "redis_version|redis_mode"
redis-cli -p $PORT module list 2>/dev/null | grep -E "^name|^bf|^ReJSON|^search"
echo "--- 启动日志尾部 ---"
tail -3 $LOG

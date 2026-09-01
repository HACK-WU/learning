#!/bin/bash
set -u
MOD=/usr/lib/redis/modules
DIR=/tmp/redis-l09
mkdir -p $DIR

# 启动 3 个实例，io-threads 分别为 1 / 4 / 8（该配置为 immutable，只能在启动时指定）
for spec in "7102:1" "7103:4" "7104:8"; do
  PORT=${spec%%:*}
  T=${spec##*:}
  redis-cli -p $PORT shutdown nosave 2>/dev/null
  sleep 0.3
  nohup redis-server \
    --port $PORT --bind 127.0.0.1 --dir $DIR --save '' --appendonly no \
    --io-threads $T \
    --loadmodule $MOD/redisbloom.so \
    > $DIR/$PORT.log 2>&1 &
done

sleep 1.5
for spec in "7102:1" "7103:4" "7104:8"; do
  PORT=${spec%%:*}
  T=${spec##*:}
  v=$(redis-cli -p $PORT config get io-threads 2>/dev/null | tail -1)
  echo "$PORT (期望 io-threads=$T) -> 实际 $v"
done

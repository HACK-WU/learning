#!/bin/bash
set -u
MOD=/usr/lib/redis/modules
DIR=/tmp/redis-l09
mkdir -p $DIR

redis-cli -p 7106 shutdown nosave 2>/dev/null
sleep 0.3
nohup redis-server --port 7106 --bind 127.0.0.1 --dir $DIR --save '' \
  --appendonly no \
  --loadmodule $MOD/redisbloom.so \
  --loadmodule $MOD/rejson.so \
  --loadmodule $MOD/redisearch.so \
  > $DIR/7106.log 2>&1 &
sleep 1.5
R="redis-cli -p 7106"
echo "=== 模块加载情况 ==="
$R module list 2>/dev/null | grep -E "^name|^search|^bf|^ReJSON"
echo ""
echo "=== FT.CREATE 是否可用 ==="
$R ft.create testidx ON hash PREFIX 1 "t:" SCHEMA a NUMERIC 2>&1 | head -2
echo ""
echo "=== listpack 阈值实测（跨实例确认） ==="
$R config get hash-max-listpack-entries
$R config get hash-max-listpack-value
echo "--- zset / list 阈值 ---"
$R config get zset-max-listpack-entries
$R config get list-max-listpack-size

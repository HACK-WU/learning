#!/usr/bin/env bash
set -u
DIR=/tmp/redis-l08
mkdir -p $DIR
echo "===== 关闭旧 7101 ====="
redis-cli -p 7101 shutdown nosave 2>/dev/null; sleep 0.5
echo "===== 用 --loadmodule 拉起 7101 ====="
redis-server --port 7101 \
  --loadmodule /usr/lib/redis/modules/redisbloom.so \
  --save '' --appendonly no --dir $DIR --dbfilename l08.rdb \
  --daemonize yes --logfile $DIR/7101.log
for i in $(seq 1 50); do redis-cli -p 7101 ping >/dev/null 2>&1 && break; sleep 0.1; done
redis-cli -p 7101 ping
echo "===== MODULE LIST ====="
redis-cli -p 7101 MODULE LIST
echo "===== BF 命令探测 ====="
redis-cli -p 7101 BF.RESERVE probe:bf 0.001 500
redis-cli -p 7101 BF.ADD probe:bf a
redis-cli -p 7101 BF.EXISTS probe:bf a
redis-cli -p 7101 BF.EXISTS probe:bf zzz
redis-cli -p 7101 BF.INFO probe:bf
redis-cli -p 7101 MEMORY USAGE probe:bf
echo "===== CF 探测（Cuckoo，支持删除）====="
redis-cli -p 7101 CF.RESERVE probe:cf 1000 2>&1 | head -2
redis-cli -p 7101 CF.ADD probe:cf a 2>&1 | head -2
redis-cli -p 7101 CF.EXISTS probe:cf a 2>&1 | head -2
redis-cli -p 7101 CF.DEL probe:cf a 2>&1 | head -2
redis-cli -p 7101 CF.EXISTS probe:cf a 2>&1 | head -2
redis-cli -p 7101 flushall
echo "===== 清理 ====="
redis-cli -p 7101 dbsize

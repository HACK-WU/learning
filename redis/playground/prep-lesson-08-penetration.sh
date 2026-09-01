#!/usr/bin/env bash
# 课 8 实验 1：缓存穿透 —— 基线、缓存空值、布隆过滤器三方案实测
set -u
PORT=7101
DIR=/tmp/redis-l08
PY=/mnt/d/projects/learning/redis/playground

mkdir -p $DIR

echo "===== 0. 拉起课 8 专用实例（端口 $PORT，无持久化）====="
redis-cli -p $PORT ping 2>/dev/null && echo "已有实例在跑，先关掉" && redis-cli -p $PORT shutdown nosave 2>/dev/null
sleep 0.5
redis-server --port $PORT \
  --loadmodule /usr/lib/redis/modules/redisbloom.so \
  --save '' --appendonly no --dir $DIR --dbfilename l08.rdb \
  --daemonize yes --logfile $DIR/$PORT.log
for i in $(seq 1 50); do
  redis-cli -p $PORT ping >/dev/null 2>&1 && break
  sleep 0.1
done
redis-cli -p $PORT ping
redis-cli -p $PORT flushall

echo
echo "===== 1. Redis 8.10.1 内置模块探测（Bloom 家族命令可用性）====="
echo "--- MODULE LIST ---"
redis-cli -p $PORT MODULE LIST 2>&1 | grep -E 'name|ver' | paste - - | head -10
echo "--- BF / CF / TOPK 命令探测 ---"
for c in "BF.RESERVE probe:bf 0.01 1000" "BF.ADD probe:bf a" "BF.EXISTS probe:bf a" \
         "BF.INFO probe:bf" "BF.DEBUG probe:bf" \
         "CF.RESERVE probe:cf 1000" "CF.ADD probe:cf a" "CF.EXISTS probe:cf a" "CF.DEL probe:cf a" \
         "TOPK.RESERVE probe:tk 50 2000 7" "BF.DEL probe:bf a"; do
  printf '%-38s => ' "$c"
  redis-cli -p $PORT $c 2>&1 | head -4 | tr '\n' '|'
  echo
done
redis-cli -p $PORT flushall >/dev/null

echo
echo "===== 2. 运行穿透实测（Python，零依赖客户端）====="
cd /tmp && python3 "$PY/prep-lesson-08-penetration.py" 2>&1

echo
echo "===== 3. 清理探测 key（保留实例供后续实验）====="
redis-cli -p $PORT flushall

echo
echo "===== 4. 实例状态 ====="
redis-cli -p $PORT dbsize
redis-cli -p $PORT info memory | grep -E 'used_memory_human|used_memory:'

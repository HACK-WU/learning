#!/bin/bash
# 7201 启动失败排查
set -u
BASE=/tmp/redis-final

echo "===== 1. 启动日志尾部 ====="
tail -20 $BASE/7201/redis.log 2>/dev/null

echo
echo "===== 2. 配置文件中的 user 行（逐行带行号） ====="
grep -n '^user' $BASE/7201/redis.conf

echo
echo "===== 3. 尝试前台启动看真实报错 ====="
timeout 3 redis-server $BASE/7201/redis.conf --port 7201 2>&1 | tail -15

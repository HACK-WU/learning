#!/usr/bin/env bash
# 课 9 环境搭建：在 6380 端口起一个干净的 Redis（不干扰 6379 上已有实例）
set -u

PORT=6380

echo "=== 1. 启动干净 Redis (port $PORT) ==="
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no \
  --logfile /tmp/redis-6380.log 2>&1 | tail -3
sleep 1.5

echo
echo "=== 2. 连通性验证 ==="
redis-cli -p "$PORT" ping

echo
echo "=== 3. 6379 上旧实例仍在运行（未被干扰） ==="
ps aux | grep '[r]edis-server' | awk '{print $2, $11, $12}'

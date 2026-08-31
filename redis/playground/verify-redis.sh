#!/usr/bin/env bash
# Redis 课程实操环境验证脚本：启动一个临时实例，跑一遍基础命令，然后清理
# 用法：bash /mnt/d/projects/learning/redis/playground/verify-redis.sh

set -u
PORT=6399
DIR=/tmp/redis-course-verify

mkdir -p "$DIR"
cd "$DIR" || exit 1

echo "=== 1. 启动临时 Redis 实例（端口 $PORT）==="
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR"
sleep 1

echo "=== 2. 连通性 ==="
redis-cli -p "$PORT" ping

echo "=== 3. 基础读写 ==="
redis-cli -p "$PORT" set course:test 'hello-redis-8'
redis-cli -p "$PORT" get course:test

echo "=== 4. 版本与运行环境 ==="
redis-cli -p "$PORT" info server | grep -E 'redis_version|^os:|executable'

echo "=== 5. 清理：关闭临时实例 ==="
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
if redis-cli -p "$PORT" ping 2>/dev/null | grep -q PONG; then
  echo "WARN: 实例仍在运行"
else
  echo "OK: 临时实例已关闭"
fi

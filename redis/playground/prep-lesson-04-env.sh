#!/usr/bin/env bash
# 课 4 备课：环境核对
PORT=6404
DIR=/tmp/redis-course-l04

echo "=== Redis 版本 ==="
redis-server --version
redis-cli --version

mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1
echo "PING: $(redis-cli -p "$PORT" ping)"

echo ""
echo "=== 与课 3 衔接的关键配置默认值 ==="
echo "-- Set 编码阈值 --"
redis-cli -p "$PORT" config get set-max-intset-entries
redis-cli -p "$PORT" config get set-max-listpack-entries
redis-cli -p "$PORT" config get set-max-listpack-value
echo "-- ZSet 编码阈值 --"
redis-cli -p "$PORT" config get zset-max-listpack-entries
redis-cli -p "$PORT" config get zset-max-listpack-value

echo ""
echo "=== 清理 ==="
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"

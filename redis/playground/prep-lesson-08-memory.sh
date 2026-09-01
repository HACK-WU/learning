#!/usr/bin/env bash
# 课 8 实验 5：内存淘汰与过期策略（独立端口 7102）
set -u
PORT=7102
PY=/mnt/d/projects/learning/redis/playground
mkdir -p /tmp/redis-l08
echo "===== 运行内存实验（耗时约 3-5 分钟）====="
cd /tmp && python3 "$PY/prep-lesson-08-memory.py" 2>&1
echo
echo "===== 清理：关闭 7102 ====="
redis-cli -p $PORT shutdown nosave 2>/dev/null || true
sleep 0.5
ss -lntp 2>/dev/null | grep ":$PORT" || echo "7102 已关闭"

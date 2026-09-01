#!/usr/bin/env bash
# 课 8 实验 2：缓存击穿
set -u
PORT=7101
PY=/mnt/d/projects/learning/redis/playground
redis-cli -p $PORT ping >/dev/null 2>&1 || echo "7101 未启动"
echo "===== 运行击穿实测 ====="
cd /tmp && python3 "$PY/prep-lesson-08-breakdown.py" 2>&1
echo
echo "===== 清理 ====="
redis-cli -p $PORT flushall

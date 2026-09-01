#!/usr/bin/env bash
# 课 8 实验 4：缓存与数据库一致性
set -u
PORT=7101
PY=/mnt/d/projects/learning/redis/playground
redis-cli -p $PORT ping >/dev/null 2>&1 || echo "7101 未启动"
echo "===== 运行一致性实测 ====="
cd /tmp && python3 "$PY/prep-lesson-08-consistency.py" 2>&1
echo
echo "===== 清理 ====="
redis-cli -p $PORT flushall

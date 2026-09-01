#!/usr/bin/env bash
# 课 8 实验 3：缓存雪崩
set -u
PORT=7101
PY=/mnt/d/projects/learning/redis/playground
redis-cli -p $PORT ping >/dev/null 2>&1 || echo "7101 未启动"
echo "===== 运行雪崩实测（约 60 秒，含两组各 26 秒观察窗）====="
cd /tmp && python3 "$PY/prep-lesson-08-avalanche.py" 2>&1
echo
echo "===== 清理 ====="
redis-cli -p $PORT flushall

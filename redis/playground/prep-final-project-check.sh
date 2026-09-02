#!/bin/bash
# 检查主程序运行状态与 Redis 侧情况
set -u

echo "===== 1. python 进程 ====="
ps aux | grep -E 'python3 main.py' | grep -v grep | head -3

echo
echo "===== 2. 7201 当前状态 ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' PING 2>/dev/null | head -1
redis-cli -p 7201 --user appuser --pass 'AppPass123!' DBSIZE 2>/dev/null | head -1
redis-cli -p 7201 --user appuser --pass 'AppPass123!' INFO stats 2>/dev/null | grep -E 'total_commands_processed|instantaneous_ops' | head -2

echo
echo "===== 3. 数据是否持续增长（判断是否在跑） ====="
sleep 2
redis-cli -p 7201 --user appuser --pass 'AppPass123!' DBSIZE 2>/dev/null | head -1

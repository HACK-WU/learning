#!/usr/bin/env bash
# 最终全量验收：跑通所有验证脚本
set -u

VENV=/mnt/d/projects/learning/celery-django/.venv
BASE=/mnt/d/projects/learning/celery-django

echo "确保 Redis 在运行..."
redis-cli -p 6380 ping > /dev/null 2>&1 || redis-server --port 6380 --daemonize yes > /dev/null 2>&1 || true
sleep 2
redis-cli -p 6380 ping 2>&1 | head -1

echo
echo "=========================================="
echo " ① 项目验收脚本 verify.sh"
echo "=========================================="
bash "$BASE/projects/电商订单履约系统/实现/verify.sh" 2>&1 | tail -25

echo
echo "=========================================="
echo " ② 幂等验证"
echo "=========================================="
bash "$BASE/playground/l10-test-idempotent.sh" 2>&1 | tail -22

echo
echo "=========================================="
echo " ③ chord 编排验证"
echo "=========================================="
bash "$BASE/playground/l10-test-chord.sh" 2>&1 | tail -12

echo
echo "=========================================="
echo " 全部验收完成"
echo "=========================================="
exit 0

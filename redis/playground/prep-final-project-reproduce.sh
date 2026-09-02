#!/bin/bash
# 评审 A6：模拟学习者从零复现 —— 先停掉现有实例，严格按 README 的两步走
# 目的：验证 README 的运行方式真的能跑通（而不是靠我中途手工修好的状态）
set -u
BASE=/tmp/redis-final

echo "########## 步骤 0：清理，回到干净的初始状态 ##########"
for p in 7201 7202 7203; do
  PID=$(ss -lntp 2>/dev/null | grep ":$p " | grep -oP 'pid=\K[0-9]+' | head -1)
  if [ -n "$PID" ]; then
    kill -TERM $PID 2>/dev/null
    echo "  已停止 $p (pid=$PID)"
  fi
done
sleep 2
rm -rf $BASE
echo "  已清除 $BASE"

echo
echo "########## 步骤 1：严格按 README 第一步 —— start.sh ##########"
bash /mnt/d/projects/learning/redis/playground/prep-final-project-start.sh 2>&1 | tail -12

echo
echo "########## 步骤 2：严格按 README 第二步 —— rebuild.sh ##########"
bash /mnt/d/projects/learning/redis/playground/prep-final-project-rebuild.sh 2>&1 | tail -20

echo
echo "########## 步骤 3：跑 main.py ##########"
cd /mnt/d/projects/learning/redis/projects/电商大促数据层/实现
timeout 200 python3 -u main.py 2>&1 | grep -E '✓|✗|提速|账目|成功数|第.幕|Traceback|Error' | head -30

echo
echo "########## 步骤 4：复现结论 ##########"
echo "  （上方若出现 ✓ 且无 Traceback，说明 README 的运行方式可直接复现）"

#!/usr/bin/env bash
# 诊断：kill -9 到底有没有真的杀掉 broker？
# 三组可疑现象：
#   1. B 组非持久化交换机重启后仍在
#   2. D 组非持久化消息重启后仍在（最反常）
#   3. broker "等待 1 秒" 就就绪 —— 正常冷启动至少要几秒
# 怀疑：pkill -9 -f beam.smp 在容器内没匹配到进程，或容器根本没停
source "$(dirname "$0")/l7-env.sh"
set -u

echo "=== 1. 容器内进程清单 ==="
"$DOCKER" exec "$RMQ_CT" ps aux 2>&1 | head -20

echo ""
echo "=== 2. beam.smp 是否存在（pkill 的匹配目标）==="
"$DOCKER" exec "$RMQ_CT" bash -c "ps aux | grep -c beam.smp" 2>&1

echo ""
echo "=== 3. pkill 是否可用 ==="
"$DOCKER" exec "$RMQ_CT" bash -c "command -v pkill || echo 'pkill 不存在'" 2>&1

echo ""
echo "=== 4. 容器启动时间与运行时长（判断有没有真重启）==="
"$DOCKER" inspect -f '启动时间: {{.State.StartedAt}}  运行状态: {{.State.Status}}  重启次数: {{.RestartCount}}' "$RMQ_CT" 2>&1

echo ""
echo "=== 5. broker 已运行秒数（uptime）==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl status 2>&1 | grep -iE "uptime|runtime" | head -3

echo ""
echo "=== 6. 容器日志尾部（看有没有真重启记录）==="
"$DOCKER" logs --tail 15 "$RMQ_CT" 2>&1

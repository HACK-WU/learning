#!/bin/bash
# 课 3 配套验证脚本：从干净状态跑一遍完整收发链路 + CLI 观察
# 用法（Windows + WSL）：
#   & "C:\Windows\System32\bash.exe" -c "bash /mnt/d/projects/learning/rabbitmq/playground/verify.sh"
#
# 前置：用讲义中的 docker run 命令起好 rabbitmq-learn 容器

cd /mnt/d/projects/learning/rabbitmq/playground

echo "===== 清理旧队列，从头演示 ====="
docker exec rabbitmq-learn rabbitmqctl delete_queue hello 2>&1 | tail -2

echo ""
echo "===== 1. 发送 ====="
python3 send.py 2>&1

echo ""
echo "===== 2. 发送后队列状态（应 messages=1、consumers=0） ====="
docker exec rabbitmq-learn rabbitmqctl list_queues name messages consumers durable type 2>&1 | tail -3

echo ""
echo "===== 3. 消费（6秒超时） ====="
timeout 6 python3 receive.py 2>&1

echo ""
echo "===== 4. 消费后队列状态（应 messages=0） ====="
docker exec rabbitmq-learn rabbitmqctl list_queues name messages consumers durable type 2>&1 | tail -3

echo ""
echo "===== 5. rabbitmqadmin（2.x 新版语法，注意不再支持列名参数） ====="
docker exec -e RABBITMQADMIN_USERNAME=learn -e RABBITMQADMIN_PASSWORD=learn123 \
  rabbitmq-learn rabbitmqadmin list queues --non-interactive 2>&1 | head -5
echo "--- exchanges ---"
docker exec -e RABBITMQADMIN_USERNAME=learn -e RABBITMQADMIN_PASSWORD=learn123 \
  rabbitmq-learn rabbitmqadmin list exchanges --non-interactive 2>&1 | head -10
echo "--- bindings ---"
docker exec -e RABBITMQADMIN_USERNAME=learn -e RABBITMQADMIN_PASSWORD=learn123 \
  rabbitmq-learn rabbitmqadmin list bindings --non-interactive 2>&1 | head -5

echo ""
echo "===== 6. 默认交换机绑定（source 为空 = 默认交换机） ====="
docker exec rabbitmq-learn rabbitmqctl list_bindings source_name destination_name routing_key 2>&1 | tail -4

echo ""
echo "===== 7. 队列类型与属性 ====="
docker exec rabbitmq-learn rabbitmqctl list_queues name durable auto_delete exclusive arguments type 2>&1 | tail -4

echo ""
echo "===== 8. 节点健康诊断 ====="
docker exec rabbitmq-learn rabbitmq-diagnostics check_running 2>&1 | tail -1
docker exec rabbitmq-learn rabbitmq-diagnostics check_port_connectivity 2>&1 | tail -1

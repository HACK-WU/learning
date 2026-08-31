#!/usr/bin/env bash
# 课5 知识点3：三种队列的资源占用与 stream 协议验证

echo "############ 1. 队列清单与类型 ############"
docker exec rabbitmq-learn rabbitmqctl list_queues name type durable messages 2>&1 | grep -vE "^(Timeout|Listing)"

echo ""
echo "############ 2. 各类型队列的内存占用 ############"
docker exec rabbitmq-learn rabbitmqctl list_queues name type memory message_bytes 2>&1 | grep -vE "^(Timeout|Listing)"

echo ""
echo "############ 3. stream 专用端口 5552 是否监听 ############"
docker exec rabbitmq-learn rabbitmq-diagnostics -q listeners 2>&1 | grep -i stream || \
docker exec rabbitmq-learn rabbitmq-diagnostics -q status 2>&1 | grep -i "5552"

echo ""
echo "############ 4. quorum 队列的副本状态（单节点）############"
docker exec rabbitmq-learn rabbitmqctl list_queues name type 2>&1 | grep quorum
echo "--- quorum 成员信息 ---"
docker exec -e RABBITMQADMIN_USERNAME=learn -e RABBITMQADMIN_PASSWORD=learn123 \
  rabbitmq-learn rabbitmqadmin list queues name type --non-interactive 2>&1 | grep -i quorum

echo ""
echo "############ 5. 检查 stream 队列是否真的存了消息 ############"
docker exec rabbitmq-learn rabbitmqctl list_queues name type messages message_bytes 2>&1 | grep -iE "stream|name"

echo ""
echo "############ 6. 官方推荐的队列类型默认值确认 ############"
docker exec rabbitmq-learn rabbitmqctl environment 2>&1 | grep -iE "default_queue_type" || echo ">>> 未显式配置 default_queue_type → 默认 classic"

echo ""
echo "############ 7. 磁盘/内存告警水位 ############"
docker exec rabbitmq-learn rabbitmqctl environment 2>&1 | grep -iE "disk_free_limit|mem_relative|memory_high" | head -5

echo ""
echo "############ 8. stream 队列的 leader/replicas（HTTP API）############"
docker exec rabbitmq-learn curl -s -u learn:learn123 http://localhost:15672/api/queues/%2F 2>/dev/null | head -c 400 || echo "(curl 不可用)"

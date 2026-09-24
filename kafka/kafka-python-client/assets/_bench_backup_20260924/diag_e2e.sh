#!/bin/bash
# 定位：端到端消费到 0 条 —— 先确认消息到底有没有进 topic
set -u
echo "=== 1. topic 列表 ==="
docker exec l9-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 --list 2>&1 | tail -10

echo ""
echo "=== 2. l9-orders-sr 各分区水位 ==="
docker exec l9-kafka-1 /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --bootstrap-server kafka-1:9092 --topic l9-orders-sr 2>&1 | tail -10

echo ""
echo "=== 3. 消费者组状态 ==="
docker exec l9-kafka-1 /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server kafka-1:9092 --group l9-sr-g --describe 2>&1 | tail -10

echo ""
echo "=== 4. 用命令行消费者直接读（绕过 Python 客户端）==="
timeout 25 docker exec l9-kafka-1 /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic l9-orders-sr \
  --from-beginning --max-messages 3 --timeout-ms 15000 2>&1 | tail -8

echo ""
echo "=== 5. 检查 _schemas topic（SR 是否真写进 Kafka）==="
docker exec l9-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 --list 2>&1 | grep -i schema

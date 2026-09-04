#!/bin/bash
set -x
echo "=== 启动 Kafka（KRaft 单节点）==="
docker rm -f doris-kafka 2>/dev/null
docker run -d --name doris-kafka \
  --network host \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093 \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://127.0.0.1:9092 \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@127.0.0.1:9093 \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  -e KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0 \
  apache/kafka:3.9.1

echo ""
echo "=== 等 25 秒让 Kafka 就绪 ==="
sleep 25

echo ""
echo "=== 检查 Kafka 容器状态 ==="
docker ps --filter name=doris-kafka --format '{{.Names}}|{{.Status}}'

echo ""
echo "=== 创建 topic: doris_orders（3 分区）==="
docker exec doris-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server 127.0.0.1:9092 \
  --create --topic doris_orders --partitions 3 --replication-factor 1 2>&1 | tail -5

echo ""
echo "=== 列出 topic ==="
docker exec doris-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server 127.0.0.1:9092 --list 2>&1 | tail -10

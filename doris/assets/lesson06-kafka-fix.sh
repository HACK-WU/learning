#!/bin/bash
set -x
echo "=== 建桥接网络 ==="
docker network create doris-net 2>&1 | tail -2

echo ""
echo "=== 把 doris-learn 接入该网络 ==="
docker network connect doris-net doris-learn 2>&1 | tail -2

echo ""
echo "=== 删掉旧的 host 网络 Kafka，改用桥接网络 ==="
docker rm -f doris-kafka 2>&1 | tail -1

echo ""
echo "=== 启动 Kafka（桥接网络，hostname=kafka，advertised 用 kafka:9092）==="
docker run -d --name doris-kafka \
  --network doris-net \
  --hostname kafka \
  -p 9092:9092 \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092 \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:9093 \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  -e KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0 \
  apache/kafka:3.9.1

echo ""
echo "=== 等 30 秒 ==="
sleep 30

echo ""
echo "=== 容器状态 ==="
docker ps --filter name=doris-kafka --format '{{.Names}}|{{.Status}}'

echo ""
echo "=== 验证 advertised.listeners ==="
docker exec doris-kafka bash -c "grep -E '^advertised.listeners' /opt/kafka/config/kraft/server.properties"

echo ""
echo "=== 创建 topic ==="
docker exec doris-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 \
  --create --topic doris_orders --partitions 3 --replication-factor 1 2>&1 | tail -3

echo ""
echo "=== 从 doris-learn 容器测试连通性 ==="
docker exec doris-learn bash -c "timeout 8 bash -c '</dev/tcp/kafka/9092' && echo 'CONNECT_OK' || echo 'CONNECT_FAIL'"

echo ""
echo "=== 列出 topic ==="
docker exec doris-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list 2>&1 | tail -5

#!/bin/bash
# 课 8 实验 6：ACL 最小权限完整闭环 —— 拒绝 → 授权 → 放行
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
ADMIN="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"
NET=stage6-observability_kafka-net

echo "=== 6-0. 重建 topic 并准备测试客户端容器 ==="
$ADMIN /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 \
  --create --if-not-exists --topic sec-ops-demo \
  --partitions 3 --replication-factor 3 2>&1 | tail -2

echo ""
echo "=== 6-1. 【拒权验证】app-writer 未授权时写入（应当被拒） ==="
printf 'unauthorized:test\n' | docker run --rm -i --network $NET \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9095 --topic sec-ops-demo \
  --producer.config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "authoriz|denied|error|exception" | head -3

echo ""
echo "=== 6-2. 【授权】给 app-writer 授予 sec-ops-demo 的 Write ==="
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --add \
  --allow-principal User:app-writer --operation Write --topic sec-ops-demo 2>&1 \
  | grep -vE '^\[20' | tail -3

echo ""
echo "=== 6-3. 【放行验证】授权后写入（应当成功） ==="
printf 'authorized:works-now\n' | docker run --rm -i --network $NET \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9095 --topic sec-ops-demo \
  --producer.config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "authoriz|denied|error|exception" | head -3
echo "（无输出 = 成功）"

echo ""
echo "=== 6-4. 确认消息真的进去了 ==="
sleep 3
$ADMIN /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>&1 | grep -vE '^\[20'

echo ""
echo "=== 6-5. 【读权限】app-reader 未授权读（应当被拒） ==="
docker run --rm --network $NET \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  timeout 15 /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9095 --topic sec-ops-demo \
  --consumer.config /etc/kafka/client/reader-sasl.properties \
  --from-beginning --max-messages 1 2>&1 \
  | grep -iE "authoriz|denied|NotAuthorized" | head -3

echo ""
echo "=== 6-6. 查看当前 ACL 全貌 ==="
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --list 2>&1 \
  | grep -vE '^\[20' | head -12

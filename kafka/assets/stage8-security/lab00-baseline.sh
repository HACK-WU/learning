#!/bin/bash
# 课 8 实验 0：建立对照组——确认当前集群"零安全"时任何人都能连
# 目的：先记录"改造前"的行为，后面开 SASL/ACL 后才有对照
EXEC="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"

echo "=== 0-1. 无凭据直连 broker-1 成功（当前 PLAINTEXT，无认证无授权） ==="
$EXEC /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 2>&1 | grep -E '^kafka-1' | head -3

echo ""
echo "=== 0-2. 创建课 8 演练 topic（RF=3, 3 分区） ==="
$EXEC /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 \
  --create --if-not-exists --topic sec-ops-demo \
  --partitions 3 --replication-factor 3 2>&1 | tail -2

echo ""
echo "=== 0-3. 无凭据即可写入（对照组：应当成功） ==="
echo "hello-before-security" | $EXEC /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo 2>&1 | tail -3
echo "（无报错即写入成功）"

echo ""
echo "=== 0-4. 无凭据即可消费（对照组：应当成功） ==="
timeout 15 $EXEC /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --from-beginning --timeout-ms 8000 2>&1 | tail -5

echo ""
echo "=== 0-5. 当前 ACL 清单（应当为空） ==="
$EXEC /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --list 2>&1 | tail -5

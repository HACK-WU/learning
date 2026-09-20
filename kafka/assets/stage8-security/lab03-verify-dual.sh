#!/bin/bash
# 课 8 实验 3：验证"先加门不锁门"—— 老客户端零中断 + 创建 SCRAM 凭据
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
EXEC="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"
PROD="docker exec -i -e KAFKA_JMX_OPTS= l15-kafka-1"

echo "=== 3-1. 【关键】老客户端 PLAINTEXT:9092 仍然可用（零中断验证） ==="
$EXEC /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 2>&1 \
  | grep -E '^kafka-[0-9]' | sed 's/ ->.*//' | head -5

echo ""
echo "=== 3-2. 老客户端仍可读写（零中断的功能验证） ==="
printf 'legacy:still-works\n' | $PROD /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --property parse.key=true --property key.separator=: 2>&1 | tail -2
sleep 2
$EXEC /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>&1 | grep -vE '^\[20' | head -4

echo ""
echo "=== 3-3. 创建 SCRAM 凭据（先建用户，供 SASL 监听器使用） ==="
echo "--- 创建 admin 用户 ---"
$EXEC /opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-1:9092 \
  --alter --entity-type users --entity-name admin \
  --add-config 'SCRAM-SHA-512=[password=admin-secret-2026]' 2>&1 | tail -3

echo "--- 创建 app-writer 用户 ---"
$EXEC /opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-1:9092 \
  --alter --entity-type users --entity-name app-writer \
  --add-config 'SCRAM-SHA-512=[password=writer-secret-2026]' 2>&1 | tail -3

echo "--- 创建 app-reader 用户 ---"
$EXEC /opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-1:9092 \
  --alter --entity-type users --entity-name app-reader \
  --add-config 'SCRAM-SHA-512=[password=reader-secret-2026]' 2>&1 | tail -3

echo ""
echo "=== 3-4. 列出已创建的用户凭据 ==="
$EXEC /opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-1:9092 \
  --describe --entity-type users 2>&1 | grep -vE '^\[20' | head -10

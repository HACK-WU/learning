#!/bin/bash
# 课 8 实验 7：干净的拒权验证 —— 先删 ACL，再测未授权访问
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
ADMIN="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"
NET=stage6-observability_kafka-net
CC="-v $(pwd)/client-config:/etc/kafka/client:ro"

echo "=== 7-1. 删除 sec-ops-demo 上 app-writer 的全部 ACL ==="
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --remove \
  --allow-principal User:app-writer --topic sec-ops-demo --force 2>&1 \
  | grep -vE '^\[20' | tail -2

echo ""
echo "=== 7-2. 确认 ACL 已清空 ==="
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --list \
  --topic sec-ops-demo 2>&1 | grep -vE '^\[20' | head -4

echo ""
echo "=== 7-3. 【关键拒权验证】app-writer 无 Write 权限时写入 ==="
printf 'should-be-denied:x\n' | docker run --rm -i --network $NET $CC \
  -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9095 --topic sec-ops-demo \
  --producer.config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "authoriz|denied|NotAuthorized|TOPIC_AUTHORIZATION" | head -4

echo ""
echo "=== 7-4. 【关键拒权验证】app-reader 无 Read 权限时消费 ==="
docker run --rm --network $NET $CC -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  timeout 18 /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9095 --topic sec-ops-demo \
  --consumer.config /etc/kafka/client/reader-sasl.properties \
  --group reader-test-cg --from-beginning --max-messages 1 2>&1 \
  | grep -iE "authoriz|denied|NotAuthorized|TOPIC_AUTHORIZATION" | head -4

echo ""
echo "=== 7-5. 【对照】admin（super user）无 ACL 也能操作 ==="
printf 'admin:super-bypass\n' | docker run --rm -i --network $NET \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  sh -c 'cat > /tmp/admin.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret-2026";
EOF
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka-1:9095 --topic sec-ops-demo --producer.config /tmp/admin.properties' 2>&1 \
  | grep -iE "authoriz|denied|error" | head -3
echo "（无输出 = super user 绕过 ACL 成功）"

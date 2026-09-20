#!/bin/bash
# 课 8 实验 8：写权限拒权 + 凭据在线轮换（滚动安全的核心）
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
ADMIN="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"
NET=stage6-observability_kafka-net
CC="-v $(pwd)/client-config:/etc/kafka/client:ro"

echo "=== 8-1. 彻底清空 sec-ops-demo 的所有 ACL ==="
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --remove \
  --topic sec-ops-demo --force 2>&1 | grep -vE '^\[20' | tail -2

echo ""
echo "=== 8-2. 用新 topic 做纯净的写拒权验证 ==="
$ADMIN /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 \
  --create --if-not-exists --topic acl-deny-demo \
  --partitions 1 --replication-factor 3 2>&1 | tail -1

echo "--- app-writer 对 acl-deny-demo 无任何 ACL，写入应当被拒 ---"
printf 'deny:x\n' | docker run --rm -i --network $NET $CC -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9095 --topic acl-deny-demo \
  --producer.config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "authoriz|denied|NotAuthorized|TOPIC_AUTHORIZATION" | head -3

echo ""
echo "--- 授权后再写，应当成功 ---"
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --add \
  --allow-principal User:app-writer --operation Write --topic acl-deny-demo 2>&1 \
  | grep -vE '^\[20' | tail -1
printf 'allow:x\n' | docker run --rm -i --network $NET $CC -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9095 --topic acl-deny-demo \
  --producer.config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "authoriz|denied|NotAuthorized" | head -3
echo "（无输出 = 授权后写入成功）"

echo ""
echo "=== 8-3. 【凭据在线轮换】改 app-writer 密码，验证旧密码失效、新密码生效 ==="
echo "--- 轮换前：用旧密码连（成功） ---"
docker run --rm --network $NET $CC -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9095 \
  --command-config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -cE '^kafka-[0-9]' | xargs -I{} echo "  成功连上节点数: {}"

echo "--- 执行轮换 ---"
$ADMIN /opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-1:9092 \
  --alter --entity-type users --entity-name app-writer \
  --add-config 'SCRAM-SHA-512=[password=ROTATED-2026-NEW]' 2>&1 | tail -1

echo "--- 轮换后：旧密码（应当失败） ---"
docker run --rm --network $NET $CC -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9095 \
  --command-config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "Authentication failed|invalid credentials" | head -2

echo "--- 轮换后：新密码（应当成功） ---"
cat > client-config/writer-rotated.properties <<'EOF'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="app-writer" password="ROTATED-2026-NEW";
EOF
docker run --rm --network $NET $CC -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9095 \
  --command-config /etc/kafka/client/writer-rotated.properties 2>&1 \
  | grep -cE '^kafka-[0-9]' | xargs -I{} echo "  成功连上节点数: {}"

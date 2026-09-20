#!/bin/bash
# 课 8 实验 4：SASL 客户端真连 —— 正反两面都测
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

# 先准备客户端配置文件（挂载进容器）
mkdir -p client-config

echo "=== 4-0. 生成客户端属性文件 ==="
cat > client-config/writer-sasl.properties <<'EOF'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="app-writer" password="writer-secret-2026";
EOF
cat > client-config/reader-sasl.properties <<'EOF'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="app-reader" password="reader-secret-2026";
EOF
cat > client-config/wrong-pwd.properties <<'EOF'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="app-writer" password="WRONG-PASSWORD";
EOF
echo "已生成 3 个客户端配置"

echo ""
echo "=== 4-1. 【反例】错误密码连 SASL 监听器（应当失败） ==="
docker run --rm --network stage6-observability_kafka-net \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" \
  -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server kafka-1:9095 \
  --command-config /etc/kafka/client/wrong-pwd.properties 2>&1 \
  | grep -iE "error|exception|failed|authentication" | head -4

echo ""
echo "=== 4-2. 【正例】正确密码连 SASL 监听器（应当成功） ==="
docker run --rm --network stage6-observability_kafka-net \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" \
  -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server kafka-1:9095 \
  --command-config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -E '^kafka-[0-9]' | sed 's/ ->.*//' | head -5

echo ""
echo "=== 4-3. 【反例】无凭据连 SASL 监听器（应当失败——证明门已存在） ==="
docker run --rm --network stage6-observability_kafka-net \
  -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  timeout 20 /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server kafka-1:9095 2>&1 | head -5

echo ""
echo "=== 4-4. 【对照】无凭据连 PLAINTEXT 监听器（仍然成功——老客户端零中断） ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-2:9092 2>&1 \
  | grep -cE '^kafka-[0-9]'

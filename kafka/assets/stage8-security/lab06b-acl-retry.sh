#!/bin/bash
# 课 8 实验 6b：重建 SCRAM 凭据后重跑 ACL 闭环
# 重要教训：SCRAM 凭据存在 __cluster_metadata（即 log.dirs）里，
#           容器重建且 log.dirs 未持久化时，凭据会一起丢失。
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
ADMIN="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"
NET=stage6-observability_kafka-net

echo "=== 6b-1. 重建 3 个 SCRAM 用户 ==="
for u in "admin:admin-secret-2026" "app-writer:writer-secret-2026" "app-reader:reader-secret-2026"; do
  NAME="${u%%:*}"; PWD="${u##*:}"
  $ADMIN /opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-1:9092 \
    --alter --entity-type users --entity-name "$NAME" \
    --add-config "SCRAM-SHA-512=[password=$PWD]" 2>&1 | tail -1
done

echo ""
echo "=== 6b-2. 【拒权验证】app-writer 未授权时写入（现在应当是被 ACL 拒绝） ==="
printf 'unauthorized:test\n' | docker run --rm -i --network $NET \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9095 --topic sec-ops-demo \
  --producer.config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "authoriz|denied|NotAuthorized|error" | head -3

echo ""
echo "=== 6b-3. 查看 ACL（此时应无 app-writer 的 Write） ==="
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --list \
  --topic sec-ops-demo 2>&1 | grep -vE '^\[20' | head -5

echo ""
echo "=== 6b-4. 【授权】给 app-writer 授予 Write ==="
$ADMIN /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --add \
  --allow-principal User:app-writer --operation Write --topic sec-ops-demo 2>&1 \
  | grep -vE '^\[20' | tail -2

echo ""
echo "=== 6b-5. 【放行验证】授权后写入（应当成功无报错） ==="
printf 'authorized:works-now\n' | docker run --rm -i --network $NET \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9095 --topic sec-ops-demo \
  --producer.config /etc/kafka/client/writer-sasl.properties 2>&1 \
  | grep -iE "authoriz|denied|NotAuthorized|error" | head -3
echo "（无输出 = 成功）"

sleep 3
echo ""
echo "=== 6b-6. 确认消息真的进去了（offset 应 > 0） ==="
$ADMIN /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>&1 | grep -vE '^\[20'

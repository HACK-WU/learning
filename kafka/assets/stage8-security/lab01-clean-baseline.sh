#!/bin/bash
# 课 8 实验 1：重建干净基线（用 -i 正确写法），并列出改造前完整状态
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
EXEC="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"
PROD="docker exec -i -e KAFKA_JMX_OPTS= l15-kafka-1"

echo "=== 1-1. 用正确写法写入 5 条消息 ==="
printf 'u1:order-created\nU2:order-paid\nu3:order-shipped\nu4:order-done\nu5:order-archived\n' | \
  $PROD /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --property parse.key=true --property key.separator=: 2>&1 | tail -2

sleep 3

echo ""
echo "=== 1-2. 确认写入成功（offset 应有变化） ==="
$EXEC /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>&1 | grep -vE '^\[20'

echo ""
echo "=== 1-3. 改造前集群完整基线（滚动变更必须留的 before 快照） ==="
echo "--- 3 个节点 listener ---"
for n in 1 2 3; do
  echo -n "  kafka-$n: "
  docker exec -e KAFKA_JMX_OPTS= l15-kafka-$n \
    grep -E "^advertised.listeners=" /opt/kafka/config/server.properties 2>&1 | tr -d '\r'
done

echo ""
echo "--- broker api versions（3 节点都应可达） ---"
$EXEC /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 2>&1 \
  | grep -E '^kafka-[0-9]' | sed 's/ ->.*//' | head -5

echo ""
echo "--- metadata quorum（控制面健康） ---"
$EXEC /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server kafka-1:9092 \
  describe --status 2>&1 | grep -E "LeaderId|LeaderEpoch|MaxFollowerLag:" | head -4

echo ""
echo "--- feature/metadata version（升级兼容性基线） ---"
$EXEC /opt/kafka/bin/kafka-features.sh --bootstrap-server kafka-1:9092 describe 2>&1 \
  | grep -E "metadata.version|FinalizedVersion" | head -3

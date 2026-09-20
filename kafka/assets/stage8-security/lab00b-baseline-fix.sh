#!/bin/bash
# 课 8 实验 0b：修正消费命令（--timeout-ms 不是 console-consumer 的参数）
EXEC="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"

echo "=== 0b-1. 无凭据消费（对照组：应当读到消息） ==="
# 说明：--timeout-ms 属于 kafka-console-consumer 的旧参数，在 4.0 里已移除，
#       报错 "Error processing message, terminating consumer process: TimeoutException"。
#       正确做法：用 --max-messages 限制条数，或外部 timeout 命令兜底。
timeout 25 $EXEC /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --from-beginning --max-messages 1 2>&1 | grep -vE "^\[.*\] " | head -5

echo ""
echo "=== 0b-2. 确认 ACL 未启用（预期 SecurityDisabledException） ==="
$EXEC /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --list 2>&1 | grep -E "SecurityDisabledException|No Authorizer" | head -2

echo ""
echo "=== 0b-3. 当前 listener 与安全协议映射 ==="
$EXEC grep -E "^(listeners|advertised.listeners|listener.security.protocol.map|inter.broker.listener.name)=" /opt/kafka/config/server.properties 2>&1

echo ""
echo "=== 0b-4. 记录改造前集群状态（滚动变更的基线） ==="
$EXEC /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 --describe --topic sec-ops-demo 2>&1 | head -8

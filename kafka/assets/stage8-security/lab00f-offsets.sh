#!/bin/bash
# 课 8 实验 0f：用有界只读命令确认消息量（避免 console-consumer 无界等待）
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

echo "=== 0f-1. 各分区 log-end-offset（证明消息确实在） ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>&1 | grep -vE '^\[20' | head -6

echo ""
echo "=== 0f-2. 用 kafka-dump-log 直接读底层日志段（绕过客户端协议层） ==="
docker exec l15-kafka-1 sh -c 'ls /tmp/kraft-logs/ | grep sec-ops' 2>&1 | head -5

echo ""
echo "=== 0f-3. dump 分区 0 的日志内容（真凭实据） ==="
DUMPDIR=$(docker exec l15-kafka-1 sh -c 'ls -d /tmp/kraft-logs/sec-ops-demo-0 2>/dev/null' | tr -d '\r')
echo "日志目录: $DUMPDIR"
if [ -n "$DUMPDIR" ]; then
  docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
    /opt/kafka/bin/kafka-dump-log.sh --files "$DUMPDIR/00000000000000000000.log" --print-data-log 2>&1 \
    | grep -vE '^\[20' | head -20
fi

echo ""
echo "=== 0f-4. 消费组 sec-ops-verify-cg 的位置（0c 那次消费是否留下了 offset） ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka-1:9092 \
  --describe --group sec-ops-verify-cg 2>&1 | grep -vE '^\[20' | head -8

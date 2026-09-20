#!/bin/bash
# 课 8 实验 0c：确认消息确实写进去了（用文件落盘，避免 grep 过滤误判）
EXEC="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"

echo "=== 0c-1. 再写 3 条带 key 的消息 ==="
printf 'k1:v1-before\nk2:v2-before\nk3:v3-before\n' | $EXEC /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --property parse.key=true --property key.separator=: 2>&1 | tail -2
echo "（无输出即成功）"

echo ""
echo "=== 0c-2. 消费到文件，再读文件（避免管道过滤误判） ==="
timeout 25 $EXEC sh -c '/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --from-beginning --max-messages 4 --property print.key=true > /tmp/lab00c.out 2>/dev/null'
$EXEC cat /tmp/lab00c.out 2>&1

echo ""
echo "=== 0c-3. 用 consumer-groups 确认这个临时消费者留下了 offset（重要：后面 ACL 要用） ==="
$EXEC /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka-1:9092 --list 2>&1 | head -10

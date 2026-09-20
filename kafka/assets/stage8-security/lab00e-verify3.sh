#!/bin/bash
# 课 8 实验 0e：最终确认可读（修正网络名 + 用独立消费组）
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

NET=$(docker network ls --format '{{.Name}}' | grep -i kafka | head -1)
echo "=== 0e-0. 实际网络名: $NET ==="

echo ""
echo "=== 0e-1. 用临时客户端容器消费（验证改造前无凭据可读） ==="
docker run --rm --network "$NET" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --from-beginning --max-messages 5 --property print.key=true 2>&1 \
  | grep -vE '^\[20' | head -10

echo ""
echo "=== 0e-2. 用独立消费组 + 指定 partition 读（排除 group 协调干扰） ==="
docker run --rm --network "$NET" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --partition 0 --offset 0 --max-messages 5 --property print.key=true 2>&1 \
  | grep -vE '^\[20' | head -10

echo ""
echo "=== 0e-3. 直接看 log-end-offset（证明消息在，与消费端无关） ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>&1 | grep -vE '^\[20' | head -6

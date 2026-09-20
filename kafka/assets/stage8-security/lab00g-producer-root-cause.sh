#!/bin/bash
# 课 8 实验 0g：定位"生产者无报错但消息没进去"的根因
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
EXEC="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"

echo "=== 0g-1. 生产者不加 -i，stdin 是否被传递？（关键怀疑点） ==="
echo "--- 方式A：echo 管道（之前用的方式） ---"
echo "pipe-test-1" | $EXEC /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo 2>&1 | tail -3
echo "退出码=$?"

echo ""
echo "--- 方式B：显式 -i 让 docker exec 保持 stdin 打开 ---"
echo "pipe-test-2" | docker exec -i -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo 2>&1 | tail -3
echo "退出码=$?"

echo ""
echo "=== 0g-2. 10 秒后再看 offset（方式B 是否真的写进去了） ==="
sleep 8
$EXEC /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>&1 | grep -vE '^\[20' | head -4

echo ""
echo "=== 0g-3. 用带 acks 与超时参数的显式生产（暴露真实错误） ==="
echo "explicit-test" | docker exec -i -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092,kafka-2:9092,kafka-3:9092 --topic sec-ops-demo \
  --request-required-acks all --timeout 10000 2>&1 | tail -5

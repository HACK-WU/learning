#!/bin/bash
# 课 8 实验 0d：用宿主机直连容器端口验证（绕过容器内重定向问题）
# 思路：端口 19192 映射到 kafka-1:9092，在 WSL 里跑一个临时客户端容器连它
# 先确认宿主机侧端口可达
echo "=== 0d-1. 宿主机侧端口连通性 ==="
for p in 19192 19193 19194; do
  if (echo > /dev/tcp/127.0.0.1/$p) 2>/dev/null; then
    echo "  port $p : OPEN"
  else
    echo "  port $p : CLOSED"
  fi
done

echo ""
echo "=== 0d-2. 用临时客户端容器连 19192 消费（验证改造前可读） ==="
docker run --rm --network kafka-observability-net \
  -e KAFKA_JMX_OPTS= \
  apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --from-beginning --max-messages 4 --property print.key=true 2>&1 | grep -vE "^\[20" | head -10

echo ""
echo "=== 0d-3. 备选：同一个 kafka-1 容器内用 --group 消费并落盘到挂载目录 ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 --topic sec-ops-demo \
  --group sec-ops-verify-cg --from-beginning --max-messages 4 \
  --property print.key=true 2>&1 | grep -vE "^\[20" | head -10

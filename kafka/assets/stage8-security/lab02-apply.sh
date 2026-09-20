#!/bin/bash
# 课 8 实验 2：应用双监听器配置 —— 演示"滚动变更"而不是"一把梭"
# 阶段一：加 SASL_PLAINTEXT 监听器，保留 PLAINTEXT，老客户端零中断
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

echo "=== 2-1. 停止旧集群（本次演示：先停后起，记录影响） ==="
docker compose down 2>&1 | tail -5

echo ""
echo "=== 2-2. 用新配置启动 ==="
docker compose up -d 2>&1 | tail -8

echo ""
echo "=== 2-3. 等待集群就绪（轮询 3 节点 API） ==="
for i in $(seq 1 30); do
  OK=$(docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
    /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 2>/dev/null \
    | grep -cE '^kafka-[0-9]')
  if [ "$OK" = "3" ]; then
    echo "  第 ${i} 次检查：3 节点全部就绪"
    break
  fi
  echo "  第 ${i} 次检查：就绪 $OK/3，等待 5 秒..."
  sleep 5
done

echo ""
echo "=== 2-4. 验证双监听器已生效 ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  grep -E "^(listeners|advertised.listeners|listener.security.protocol.map|sasl.enabled.mechanisms|inter.broker.listener.name)=" \
  /opt/kafka/config/server.properties 2>&1

echo ""
echo "=== 2-5. 关键验证：老客户端（PLAINTEXT:9092）仍然可用 ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 2>&1 \
  | grep -E '^kafka-[0-9]' | sed 's/ ->.*//' | head -5

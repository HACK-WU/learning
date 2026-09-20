#!/bin/bash
# 课 8 实验 2b：修正 KAFKA_OPTS 后重新启动
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

echo "=== 2b-1. 清理并重建 ==="
docker compose down --remove-orphans 2>&1 | tail -3
docker compose up -d 2>&1 | tail -6

echo ""
echo "=== 2b-2. 等 30 秒让集群完成选主 ==="
sleep 30

echo ""
echo "=== 2b-3. 容器状态 ==="
docker compose ps 2>&1 | grep -E "kafka|prom|grafana" | head -8

echo ""
echo "=== 2b-4. kafka-1 启动日志（找 SASL 相关） ==="
docker logs l15-kafka-1 2>&1 | grep -iE "sasl|scram|listener|error|exception" | head -10

echo ""
echo "=== 2b-5. 验证双监听器配置生效 ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  grep -E "^(listeners|advertised.listeners|listener.security.protocol.map|sasl.enabled.mechanisms|inter.broker.listener.name)=" \
  /opt/kafka/config/server.properties 2>&1

#!/bin/bash
# 课 8 实验 5：开启 ACL（Authorizer）—— 第三幕核心
# 关键：authorizer 只能在所有 broker 都配好后才生效，且必须先把 super user / broker 自身权限配好
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

echo "=== 5-0. 说明：开启 authorizer 前必须先准备"逃生通道" ==="
echo "  - super.users：admin 用户，避免把自己锁在门外"
echo "  - broker 间通信用的是 PLAINTEXT 监听器（无 ACL 校验），所以暂不需要给 broker 授权"
echo ""

echo "=== 5-1. 先记录未开 ACL 时 app-reader 能读（对照组） ==="
docker run --rm --network stage6-observability_kafka-net \
  -v "$(pwd)/client-config:/etc/kafka/client:ro" -e KAFKA_JMX_OPTS= apache/kafka:4.0.0 \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server kafka-1:9095 \
  --command-config /etc/kafka/client/reader-sasl.properties 2>&1 \
  | grep -cE '^kafka-[0-9]' | xargs -I{} echo "  可读节点数: {}"

echo ""
echo "=== 5-2. 停止集群，准备加 authorizer 配置 ==="
docker compose down 2>&1 | tail -2
echo "已停止"

#!/bin/bash
# 课 8 实验 5b：带 authorizer 启动 + ACL 最小权限实测
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1

echo "=== 5b-1. 启动带 authorizer 的集群 ==="
docker compose up -d 2>&1 | tail -4
sleep 35

echo ""
echo "=== 5b-2. 确认 authorizer 已生效 ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  grep -E "^(authorizer.class.name|super.users|allow.everyone.if.no.acl.found)=" \
  /opt/kafka/config/server.properties 2>&1

echo ""
echo "=== 5b-3. ACL 命令现在可用了（对比：之前是 SecurityDisabledException） ==="
docker exec -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-acls.sh --bootstrap-server kafka-1:9092 --list 2>&1 \
  | grep -vE '^\[20' | head -5
echo "（空列表 = 已启用但无 ACL；有 SecurityDisabledException = 未启用）"

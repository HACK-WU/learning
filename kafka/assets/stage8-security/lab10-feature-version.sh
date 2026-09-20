#!/bin/bash
# 课 8 实验 10：feature / metadata version —— 升级兼容性的判据
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
ADMIN="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"

echo "=== 10-1. 当前所有 feature 的 finalized 版本 ==="
$ADMIN /opt/kafka/bin/kafka-features.sh --bootstrap-server kafka-1:9092 describe 2>&1 \
  | grep -vE '^\[20'

echo ""
echo "=== 10-2. 关键：metadata.version 的 supported 范围 ==="
echo "（决定能否从旧版本滚动升级，以及升级后能否降级）"
$ADMIN /opt/kafka/bin/kafka-features.sh --bootstrap-server kafka-1:9092 describe 2>&1 \
  | grep -i "metadata.version"

echo ""
echo "=== 10-3. 【降级演练】尝试把 metadata.version 降到旧版本 ==="
echo "--- 先尝试降级到 3.9-IV0（如果集群在用新特性，会被拒绝） ---"
$ADMIN /opt/kafka/bin/kafka-features.sh --bootstrap-server kafka-1:9092 \
  downgrade --metadata 3.9-IV0 2>&1 | grep -vE '^\[20' | head -6

echo ""
echo "--- 尝试降级到 4.0-IV0（同大版本内的小步降级） ---"
$ADMIN /opt/kafka/bin/kafka-features.sh --bootstrap-server kafka-1:9092 \
  downgrade --metadata 4.0-IV0 2>&1 | grep -vE '^\[20' | head -6

echo ""
echo "=== 10-4. 降级后的版本确认 ==="
$ADMIN /opt/kafka/bin/kafka-features.sh --bootstrap-server kafka-1:9092 describe 2>&1 \
  | grep -i "metadata.version"

echo ""
echo "=== 10-5. 尝试降级到一个不存在的版本（验证输入校验） ==="
$ADMIN /opt/kafka/bin/kafka-features.sh --bootstrap-server kafka-1:9092 \
  downgrade --metadata 99.9-IV9 2>&1 | grep -viE '^\[20' | head -4

#!/bin/bash
# 课 8 实验 9：真跑滚动重启 —— 分批 + 每批健康检查 + 暂停条件
# 这是本课"变更审批"知识点的落地：一次只动一个节点，动完必须体检通过才动下一个
cd /mnt/d/projects/learning/kafka/assets/stage6-observability || exit 1
ADMIN="docker exec -e KAFKA_JMX_OPTS= l15-kafka-1"

health_check() {
  echo "  [体检] ..."
  local N URP LEADER
  N=$($ADMIN /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 2>/dev/null | grep -cE '^kafka-[0-9]')
  URP=$(curl -sS http://localhost:17071/metrics 2>/dev/null | grep -E '^kafka_server_replicamanager_underreplicatedpartitions' | awk '{print $2}')
  LEADER=$($ADMIN /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server kafka-1:9092 describe --status 2>/dev/null | grep -E '^LeaderId' | awk '{print $2}')
  echo "  [体检] 在线节点=$N  URP=${URP:-N/A}  ControllerLeader=$LEADER"
  if [ "$N" != "3" ]; then echo "  [体检] ❌ 节点数 != 3，暂停！"; return 1; fi
  if [ -n "$URP" ] && [ "$(echo "$URP > 0" | bc 2>/dev/null)" = "1" ]; then
    echo "  [体检] ⚠️  URP=$URP 非 0，暂停观察！"; return 1
  fi
  echo "  [体检] ✅ 通过"; return 0
}

echo "=== 9-0. 变更开始前：建立 before 基线 ==="
$ADMIN /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 --describe \
  --topic sec-ops-demo 2>/dev/null | head -5
echo "--- 初始体检 ---"
health_check

for NODE in 1 2 3; do
  echo ""
  echo "=========================================="
  echo "=== 批次 ${NODE}/3：滚动重启 l15-kafka-${NODE} ==="
  echo "=========================================="

  echo "  步骤1: 停节点 ${NODE}"
  docker compose stop kafka-${NODE} 2>&1 | tail -1

  echo "  步骤2: 停后立即体检（预期：节点数下降 → 触发暂停条件）"
  health_check || echo "  → 已触发暂停条件，等待观察..."

  echo "  步骤3: 启动节点 ${NODE}"
  docker compose start kafka-${NODE} 2>&1 | tail -1

  echo "  步骤4: 等待节点 ${NODE} 回归（最多 60 秒）"
  for i in $(seq 1 12); do
    N=$($ADMIN /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka-1:9092 2>/dev/null | grep -cE '^kafka-[0-9]')
    if [ "$N" = "3" ]; then echo "  第 ${i} 次：3 节点全部回归"; break; fi
    sleep 5
  done

  echo "  步骤5: 本批次健康检查（不通过则中止整个变更）"
  if ! health_check; then
    echo "  ❌ 批次 ${NODE} 体检未通过，中止后续变更！"
    exit 1
  fi
  echo "  ✅ 批次 ${NODE} 完成，可进入下一批"
done

echo ""
echo "=== 9-9. 变更后：after 快照（与 before 对比） ==="
$ADMIN /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 --describe \
  --topic sec-ops-demo 2>/dev/null | head -5
echo ""
echo "=== 变更后业务可用性验证（写入 + 读取） ==="
printf 'post-rolling:alive\n' | docker exec -i -e KAFKA_JMX_OPTS= l15-kafka-1 \
  /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo 2>&1 | tail -1
sleep 2
$ADMIN /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka-1:9092 \
  --topic sec-ops-demo --time -1 2>/dev/null | grep -vE '^\[20'

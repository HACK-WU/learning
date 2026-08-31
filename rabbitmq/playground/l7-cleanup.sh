#!/usr/bin/env bash
# 课 7 环境清理：删除 l7*/l7.* 测试队列与交换机，保留教学队列 hello
source "$(dirname "$0")/l7-env.sh"
set -u

echo "=== 清理前 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>&1 | sort

echo ""
echo "=== 删除测试队列 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name -q 2>/dev/null \
  | grep -E '^(l7[._])' \
  | while read -r q; do
      [ -z "$q" ] && continue
      "$DOCKER" exec "$RMQ_CT" rabbitmqctl delete_queue "$q" >/dev/null 2>&1 \
        && echo "  已删队列: $q" || echo "  删除失败: $q"
    done

echo ""
echo "=== 删除测试交换机（rabbitmqctl 无 delete_exchange，用 rabbitmqadmin）==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_exchanges name -q 2>/dev/null \
  | grep -E '^(l7[._])' \
  | while read -r e; do
      [ -z "$e" ] && continue
      "$DOCKER" exec -e RABBITMQADMIN_USERNAME="$RMQ_USER" \
                     -e RABBITMQADMIN_PASSWORD="$RMQ_PASS" \
        "$RMQ_CT" rabbitmqadmin delete exchange --name "$e" --non-interactive >/dev/null 2>&1 \
        && echo "  已删交换机: $e" || echo "  删除失败(可能不存在): $e"
    done

echo ""
echo "=== 清理后 ==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_queues name messages -q 2>&1 | sort
echo ""
echo "=== 剩余交换机（非系统）==="
"$DOCKER" exec "$RMQ_CT" rabbitmqctl list_exchanges name -q 2>&1 \
  | grep -vE '^(amq\.|$|name)' | sort

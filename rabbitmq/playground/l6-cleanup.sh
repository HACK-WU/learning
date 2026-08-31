#!/usr/bin/env bash
# 课 6 环境清理：删除所有 l6_* / l5_* 测试队列，保留教学队列 hello
# 注意：rabbitmqctl 没有 delete_exchange，交换机删除用 rabbitmqadmin 或 HTTP API
export PYTHONIOENCODING=utf-8

echo "=== 清理前 ==="
docker exec rabbitmq-learn rabbitmqctl list_queues name -q 2>&1 | sort

echo ""
echo "=== 删除测试队列 ==="
docker exec rabbitmq-learn rabbitmqctl list_queues name -q 2>/dev/null \
  | grep -E '^(l4_|l5_|l6_)' \
  | while read -r q; do
      [ -z "$q" ] && continue
      docker exec rabbitmq-learn rabbitmqctl delete_queue "$q" >/dev/null 2>&1 \
        && echo "  已删队列: $q" || echo "  删除失败: $q"
    done

echo ""
echo "=== 删除测试交换机（用 rabbitmqadmin，无 delete_exchange 命令）==="
docker exec rabbitmq-learn rabbitmqctl list_exchanges name -q 2>/dev/null \
  | grep -E '^(l4_|l5_|l6_|t_|order\.dlx)' \
  | while read -r e; do
      [ -z "$e" ] && continue
      docker exec -e RABBITMQADMIN_USERNAME=learn -e RABBITMQADMIN_PASSWORD=learn123 \
        rabbitmq-learn rabbitmqadmin delete exchange --name "$e" --non-interactive >/dev/null 2>&1 \
        && echo "  已删交换机: $e" || echo "  删除失败(可能不存在): $e"
    done

echo ""
echo "=== 清理后 ==="
docker exec rabbitmq-learn rabbitmqctl list_queues name messages -q 2>&1 | sort
echo ""
echo "=== 剩余交换机 ==="
docker exec rabbitmq-learn rabbitmqctl list_exchanges name -q 2>&1 | sort

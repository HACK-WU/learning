#!/usr/bin/env bash
NS=blueking
echo "=== 1. 创建测试 topic ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-topics.sh --create --topic bk-verify-test \
  --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092 2>&1 | tail -3

echo ""
echo "=== 2. 列出 topic（证明服务可用） ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-topics.sh --list --bootstrap-server localhost:9092 2>&1 | head -20

echo ""
echo "=== 3. 发 10 条消息 ==="
for i in $(seq 1 10); do echo "verify-msg-$i"; done | \
  kubectl exec -i -n $NS bk-kafka-0 -- kafka-console-producer.sh \
  --topic bk-verify-test --bootstrap-server localhost:9092 2>&1 | tail -2
echo "  (producer 无报错即成功)"

echo ""
echo "=== 4. 消费回来（证明端到端通） ==="
timeout 25 kubectl exec -n $NS bk-kafka-0 -- kafka-console-consumer.sh \
  --topic bk-verify-test --from-beginning --bootstrap-server localhost:9092 \
  --max-messages 10 2>&1 | grep -v '^$' | head -12

echo ""
echo "=== 5. 消费组列表（证明有真实业务在跑） ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-consumer-groups.sh --list \
  --bootstrap-server localhost:9092 2>&1 | head -10

echo ""
echo "=== 6. 清理测试 topic ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-topics.sh --delete --topic bk-verify-test \
  --bootstrap-server localhost:9092 2>&1 | tail -2

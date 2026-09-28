#!/usr/bin/env bash
NS=blueking
echo "=== KAFKA POD ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep kafka

echo ""
echo "=== KAFKA 日志尾部 ==="
kubectl logs -n $NS bk-kafka-0 --tail=6 2>&1 | tail -6

echo ""
echo "=== KAFKA 事件（是否被探针杀） ==="
kubectl describe pod -n $NS bk-kafka-0 2>/dev/null | sed -n '/Events:/,$p' | tail -6

echo ""
echo "=== 9092 端口是否通 ==="
kubectl exec -n $NS bk-kafka-0 -- bash -c 'timeout 5 bash -c "</dev/tcp/127.0.0.1/9092" && echo "  9092 OPEN" || echo "  9092 CLOSED"' 2>&1 | tail -2

echo ""
echo "=== MEM ==="
free -g | sed -n '1,2p'

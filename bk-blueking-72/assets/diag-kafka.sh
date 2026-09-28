#!/usr/bin/env bash
NS=blueking
echo "=== 1. kafka 日志（真实报错） ==="
kubectl logs -n $NS bk-kafka-0 --tail=25 2>&1 | tail -20 | sed 's/^/  /'

echo ""
echo "=== 2. kafka 事件 ==="
kubectl describe pod -n $NS bk-kafka-0 2>/dev/null | sed -n '/Events:/,$p' | tail -8 | sed 's/^/  /'

echo ""
echo "=== 3. kafka 资源与 zookeeper 连通 ==="
kubectl get pod -n $NS bk-kafka-0 -o jsonpath='{.spec.containers[0].resources}' 2>/dev/null | sed 's/^/  /'
echo ""
echo "  zk: $(kubectl get pods -n $NS bk-kafka-zookeeper-0 --no-headers 2>/dev/null | awk '{print $3}')"

echo ""
echo "=== 4. bkrepo-opdata 日志 ==="
kubectl logs -n $NS bk-repo-bkrepo-opdata-55d57977f-nw62g --tail=20 2>&1 | tail -15 | sed 's/^/  /'

echo ""
echo "=== 5. influxdb-proxy Init 卡住原因 ==="
kubectl describe pod -n $NS bk-monitor-influxdb-proxy-76f888568f-xvh79 2>/dev/null | sed -n '/Init Containers:/,/Containers:/p' | head -20 | sed 's/^/  /'

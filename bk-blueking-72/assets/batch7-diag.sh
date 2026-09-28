#!/usr/bin/env bash
NS=blueking

echo "=== 1. curl pod 为什么起不来（看事件） ==="
kubectl run dbg7 --image=curlimages/curl:8.5.0 -n $NS -- sleep 60 >/dev/null 2>&1
sleep 12
kubectl get pod -n $NS dbg7 --no-headers 2>/dev/null | awk '{print "    "$1" "$3}'
kubectl describe pod -n $NS dbg7 2>/dev/null | grep -A3 -iE 'events|failed|error' | head -8

echo ""
echo "=== 2. 用已有 pod 里的 python 发请求（绕开起新 pod） ==="
pod=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-detect-' | head -1 | awk '{print $1}')
kubectl exec -n $NS $pod -- python -c "
import socket
for host,port in [('bk-monitor-transfer-default',10202),('bk-redis-master',6379),('bk-influxdb',8086),('bk-kafka',9092),('bk-rabbitmq',5672)]:
    s=socket.socket(); s.settimeout(5)
    try:
        s.connect((host,port)); print('  %-32s %-6s OPEN' % (host,port))
    except Exception as e:
        print('  %-32s %-6s FAIL %s' % (host,port,str(e)[:40]))
    s.close()
" 2>&1 | grep -E 'OPEN|FAIL'

echo ""
echo "=== 3. transfer 的 svc 真实端口（别猜） ==="
kubectl get svc -n $NS bk-monitor-transfer-default -o jsonpath='{.spec.ports[*].port}' 2>/dev/null | sed 's/ /\n  /g' | sed 's/^/  /'

echo ""
echo "=== 4. 清理 ==="
kubectl delete pod -n $NS dbg7 >/dev/null 2>&1

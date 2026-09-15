#!/usr/bin/env bash
# HPA 真实扩容验证：对 web 层施加 CPU 压力，观察副本数增长
set -uo pipefail
NS=shop3t

echo "=== 扩容前 ==="
kubectl get hpa -n $NS web --no-headers
kubectl get deploy -n $NS web -o jsonpath='replicas={.spec.replicas}{"\n"}'

echo ""
echo "=== 施加 CPU 压力（并发打 /burn 端点）==="
WEBPODS=$(kubectl get pod -n $NS -l app=web --no-headers | awk '{print $1}')
# 后台并发压测：每个 web Pod 起 4 个 burn 请求，持续 60 秒
for P in $WEBPODS; do
  for i in 1 2 3 4; do
    kubectl exec -n $NS "$P" -- python -c '
import urllib.request
try:
    urllib.request.urlopen("http://localhost:8080/burn?seconds=60", timeout=90).read()
except Exception as e:
    pass
' >/dev/null 2>&1 &
  done
done
echo "  已发起 $(echo "$WEBPODS" | wc -w) x 4 = $(( $(echo "$WEBPODS" | wc -w) * 4 )) 个压测请求"

echo ""
echo "=== 观察 90 秒（HPA 每 15 秒可扩 100%）==="
for i in $(seq 1 18); do
  sleep 5
  R=$(kubectl get deploy -n $NS web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  U=$(kubectl get hpa -n $NS web -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  echo "  [$((i*5))s] readyReplicas=${R:-0}  cpu=${U:-?}%"
done

echo ""
echo "=== 扩容后 ==="
kubectl get hpa -n $NS web --no-headers
kubectl get deploy -n $NS web -o jsonpath='replicas={.spec.replicas}{"\n"}'
kubectl get pod -n $NS -l app=web --no-headers

echo ""
echo "=== HPA 事件 ==="
kubectl get events -n $NS --sort-by=.lastTimestamp 2>/dev/null | grep -i "horizontalpodautoscaler" | tail -6

echo ""
echo "=== 等待后台压测结束 ==="
wait 2>/dev/null
echo "  done"

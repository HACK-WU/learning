#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "=== svc-mysql Pod 状态 ==="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep '^bkpaas3-svc-mysql' | awk '{printf "  %-52s %-10s %s\n", $1, $3, $4}'

echo "=== 直连 svc-mysql-web Pod IP ==="
IP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep '^bkpaas3-svc-mysql-web' | awk '{print $1}' | head -1)
IP=$(kubectl get pod "$IP" -n "$NS" -o jsonpath='{.status.podIP}' 2>/dev/null)
echo "  podIP=${IP:-无}"
[ -n "$IP" ] && kubectl run sm-p -n "$NS" --rm -i --restart=Never --image=curlimages/curl:8.5.0 --timeout=40s -- \
  curl -s -o /dev/null -w "  HTTP=%{http_code} 大小=%{size_download}\n" --max-time 12 "http://$IP:80/" 2>&1 | tail -2

echo "=== 对比 svc-otel-web（应正常）==="
IP2=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep '^bkpaas3-svc-otel-web' | awk '{print $1}' | head -1)
IP2=$(kubectl get pod "$IP2" -n "$NS" -o jsonpath='{.status.podIP}' 2>/dev/null)
echo "  podIP=${IP2:-无}"
[ -n "$IP2" ] && kubectl run so-p -n "$NS" --rm -i --restart=Never --image=curlimages/curl:8.5.0 --timeout=40s -- \
  curl -s -o /dev/null -w "  HTTP=%{http_code} 大小=%{size_download}\n" --max-time 12 "http://$IP2:80/" 2>&1 | tail -2

echo "=== svc-mysql-web 日志末尾 ==="
M=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep '^bkpaas3-svc-mysql-web' | awk '{print $1}' | head -1)
[ -n "$M" ] && kubectl logs "$M" -n "$NS" --tail=8 2>&1 | grep -viE 'insecure|deprecat|warnings' | sed 's/^/  /'

#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. paas3 migrate-db job 状态 ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -E 'migrate-db|init-data|init-devops' | awk '{printf "  %-46s %-10s %s\n", $1, $2, $3}'
echo ""
echo "  --- 对应 Pod ---"
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'migrate-db|init-data|init-devops' | awk '{printf "  %-46s %-14s %s\n", $1, $3, $2}'

echo ""
echo "===== 2. migrate-db Pod 日志（看卡在哪）====="
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'migrate-db' | awk '{print $1}' | head -1)
[ -n "$MP" ] && kubectl logs $MP -n $NS 2>&1 | tail -20 | sed 's/^/    /' || echo "  未找到 migrate-db Pod"

echo ""
echo "===== 3. apigateway core-api 能不能访问（sync_api 的目标）====="
kubectl exec -n $NS deploy/bk-apigateway-dashboard -- \
  curl -s -o /dev/null -w "  dashboard->core-api: HTTP %{http_code}\n" \
  http://bk-apigateway-core-api.$NS.svc.cluster.local:80/ 2>&1 | tail -3

echo ""
echo "===== 4. apigateway core-api 日志（有没有报错）====="
kubectl logs -n $NS deploy/bk-apigateway-core-api 2>&1 | tail -12 | sed 's/^/    /'

echo ""
echo "===== 5. apigateway operator 日志（网关同步可能是它负责）====="
kubectl logs -n $NS deploy/bk-apigateway-operator 2>&1 | tail -12 | sed 's/^/    /'

echo ""
echo "===== 6. 有没有 apigateway 相关的 CRD 资源 ====="
kubectl get crd --no-headers 2>/dev/null | grep -iE 'apigw|gateway' | awk '{print "  "$1}'

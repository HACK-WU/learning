#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 看 paas3-apiserver 的 init 容器卡在哪 ====="
P=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3-apiserver-web' | awk '{print $1}' | head -1)
echo "  Pod: $P"
kubectl get pod $P -n $NS -o jsonpath='{.status.initContainerStatuses[*].name}' 2>/dev/null | tr ' ' '\n' | sed 's/^/    init容器: /'
echo ""
kubectl describe pod $P -n $NS 2>/dev/null | sed -n '/Init Containers:/,/Containers:/p' | head -25 | sed 's/^/  /'

echo ""
echo "===== 2. init 容器日志 ====="
kubectl logs $P -n $NS -c $(kubectl get pod $P -n $NS -o jsonpath='{.status.initContainerStatuses[0].name}' 2>/dev/null) 2>&1 | tail -15 | sed 's/^/    /'

echo ""
echo "===== 3. cmdb-apigw 错误日志 ====="
kubectl logs bk-cmdb-apigw-1-kd25r -n $NS 2>&1 | tail -15 | sed 's/^/    /'

echo ""
echo "===== 4. gse-apigw-sync 错误日志 ====="
kubectl logs bk-gse-apigw-sync-1-5zgjf -n $NS 2>&1 | tail -15 | sed 's/^/    /'

echo ""
echo "===== 5. bkiam-saas-apigateway-sync 日志 ====="
kubectl logs bkiam-saas-apigateway-sync-1-xzjlj -n $NS 2>&1 | tail -15 | sed 's/^/    /'

echo ""
echo "===== 6. first 批 bk-apigateway 到底好了没（根因嫌疑）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'apigateway|bk-apigw' | awk '{printf "  %-46s %-14s %s\n", $1, $3, $2}'

echo ""
echo "===== 7. apigateway 相关 service ====="
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -iE 'apigw|apigateway' | awk '{printf "  %-40s %-16s %s\n", $1, $2, $5}'

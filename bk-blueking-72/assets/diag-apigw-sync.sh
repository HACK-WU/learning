#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 5 个 apigw 相关异常 Pod ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'apigw|synchronization' | grep -v Running | awk '{printf "  %-50s %-20s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 2. 逐个抓日志（关键 15 行）====="
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'apigw|synchronization' | grep -v Running | awk '{print $1}'); do
  echo "  ============ $p ============"
  kubectl logs $p -n $NS --tail=25 2>&1 | grep -viE 'InsecureKeyLength|Deprecation|warnings.warn|_jws' | tail -18 | sed 's/^/    /'
  echo ""
done

echo "===== 3. bk-apigateway 所有组件状态 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bk-apigateway' | awk '{printf "  %-50s %-14s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 4. apigw svc 清单 ====="
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -iE 'apigw|apigateway' | awk '{printf "  %-34s %-12s %s\n", $1, $2, $5}'

echo ""
echo "===== 5. apigw 相关 ingress ====="
kubectl get ingress -n $NS --no-headers 2>/dev/null | grep -iE 'apigw|bkapi' | awk '{printf "  %-24s hosts=%s\n", $1, $3}'

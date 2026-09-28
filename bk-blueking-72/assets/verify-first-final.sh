#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
NS=blueking

echo "===== 1. 三个 release 状态 ====="
helm list -n "$NS" --no-headers 2>/dev/null | awk '{printf "  %-16s %-10s %s\n", $1, $8, $2}'

echo ""
echo "===== 2. 全部 Pod 就绪情况 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn
echo "  总 Pod: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"

echo ""
echo "===== 3. 非 Running/Completed 的 Pod（若有）====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{print "  "$1"  "$3}' || true

echo ""
echo "===== 4. apigateway 组件（first 批第三个）====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'apigw|apigateway' | awk '{printf "  %-52s %s\n", $1, $3}'

echo ""
echo "===== 5. 服务暴露情况 ====="
kubectl get svc -n "$NS" --no-headers 2>/dev/null | grep -iE 'bkrepo|bkauth|apigw' | awk '{printf "  %-40s %-12s %s\n", $1, $2, $5}'

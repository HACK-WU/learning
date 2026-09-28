#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. apigw 上是否注册了 bk-gse / bk-monitor ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'apigw|apigateway' | head -10 | sed 's/^/  /'

echo ""
echo "===== 2. 监控的 apigw sync job 状态 ====="
kubectl get jobs -n blueking --no-headers 2>/dev/null | grep -iE 'monitor' | head -10 | sed 's/^/  /'

echo ""
echo "===== 3. unify-query apigw sync 是否成功（Completed 说明网关通）====="
kubectl logs -n blueking job/bk-monitor-unify-query-apigw-sync 2>/dev/null | tail -15 | sed 's/^/  /'
P=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'unify-query-apigw-sync' | awk '{print $1}' | head -1)
[ -n "$P" ] && kubectl logs -n blueking "$P" 2>/dev/null | tail -15 | sed 's/^/  /'

echo ""
echo "===== 4. 关键：GSE 是否已给 monitor 授权（查 gse 的 api 白名单）====="
kubectl exec -n blueking deploy/bk-gse-admin -- env 2>/dev/null | grep -iE 'APP_CODE|APP_SECRET|BKAPP' | head -10 | sed 's/^/  /'

echo ""
echo "===== 5. 直接测试 bkapi 网关到 gse 的连通性 ====="
kubectl run curltest --rm -i --restart=Never --image=curlimages/curl:latest -n blueking -- \
  curl -s -o /dev/null -w "http_code=%{http_code}\n" http://bkapi.paas.example.com/api/bk-gse/prod/ 2>&1 | tail -5 | sed 's/^/  /'

echo ""
echo "===== 6. migrate job 完整报错中的 403 上下文 ====="
kubectl logs -n blueking bk-monitor-migrate-1-2htvr -c on-migrate 2>/dev/null | tail -8 | sed 's/^/  /'

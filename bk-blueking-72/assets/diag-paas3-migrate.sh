#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. migrate-db Job 完整描述（看失败原因）====="
kubectl describe job bkpaas3-apiserver-migrate-db-1 -n $NS 2>&1 | tail -30 | sed 's/^/  /'

echo ""
echo "===== 2. 找 migrate-db 的 Pod（可能已被清理）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3-apiserver-migrate-db' | awk '{printf "  %-46s %-14s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 3. 用 previous 看崩溃前日志 ====="
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3-apiserver-migrate-db' | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  echo "  Pod: $MP"
  echo "  --- 完整日志最后 40 行 ---"
  kubectl logs $MP -n $NS --tail=40 2>&1 | sed 's/^/    /'
  echo "  --- previous 容器日志 ---"
  kubectl logs $MP -n $NS --previous 2>&1 | tail -20 | sed 's/^/    /'
fi

echo ""
echo "===== 4. init-data / init-devops 的 init 在等什么 ====="
kubectl get pod bkpaas3-apiserver-init-data-1-mlzk6 -n $NS -o jsonpath='{.status.initContainerStatuses[0].name}' 2>/dev/null | sed 's/^/  init容器: /'
echo ""
kubectl logs bkpaas3-apiserver-init-data-1-mlzk6 -n $NS 2>&1 | tail -5 | sed 's/^/    /'

echo ""
echo "===== 5. 检查 paas3 依赖的 svc 是否就绪（bkrepo/mysql/rabbitmq/otel）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bkpaas3-svc' | awk '{printf "  %-46s %-14s %s\n", $1, $3, $2}'

echo ""
echo "===== 6. bk-repo 是否真可用（paas3 依赖它存源码包）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bkrepo' | awk '{printf "  %-46s %-14s %s\n", $1, $3, $2}'

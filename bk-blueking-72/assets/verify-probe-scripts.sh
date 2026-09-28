#!/usr/bin/env bash
# 方案C前置：看清探针脚本到底在做什么，再决定改哪个参数
set -uo pipefail
NS=blueking

echo "===== 1. liveness 脚本内容 ====="
kubectl exec bk-redis-cluster-0 -n $NS -- cat /scripts/ping_liveness_local.sh 2>/dev/null

echo ""
echo "===== 2. readiness 脚本内容 ====="
kubectl exec bk-redis-cluster-0 -n $NS -- cat /scripts/ping_readiness_local.sh 2>/dev/null

echo ""
echo "===== 3. 实际执行结果（判断当前是否还 unhealthy）====="
kubectl exec bk-redis-cluster-0 -n $NS -- sh -c '/scripts/ping_liveness_local.sh 5; echo "liveness exit=$?"' 2>&1 | tail -3
kubectl exec bk-redis-cluster-0 -n $NS -- sh -c '/scripts/ping_readiness_local.sh 1; echo "readiness exit=$?"' 2>&1 | tail -3

echo ""
echo "===== 4. 各 Pod 重启次数（判断探针是否还在杀）====="
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  echo "  $p: restarts=$(kubectl get pod $p -n $NS -o jsonpath='{.status.containerStatuses[0].restartCount}')"
done

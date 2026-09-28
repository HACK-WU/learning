#!/usr/bin/env bash
# 用途：诊断 bk-redis-cluster-2 CrashLoopBackOff 根因
set -uo pipefail
NS=blueking
POD=bk-redis-cluster-2

echo "===== 1. Pod 描述（关键段）====="
kubectl describe pod "$POD" -n "$NS" 2>&1 | grep -A25 'Events:' | tail -20

echo ""
echo "===== 2. 容器日志（当前）====="
kubectl logs "$POD" -n "$NS" --tail=40 2>&1 | head -45

echo ""
echo "===== 3. 上一次崩溃的日志 ====="
kubectl logs "$POD" -n "$NS" --previous --tail=40 2>&1 | head -45

echo ""
echo "===== 4. 环境变量中的密码/配置 ====="
kubectl exec "$POD" -n "$NS" -- env 2>&1 | grep -iE 'redis|password|auth' | head -10

echo ""
echo "===== 5. StatefulSet 的 redis-cluster 配置 ====="
kubectl get statefulset bk-redis-cluster -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].env}' 2>&1 | head -c 1500

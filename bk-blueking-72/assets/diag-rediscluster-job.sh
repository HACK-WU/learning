#!/usr/bin/env bash
# 用途：查 redis-cluster 组建集群的 Job 是否存在、是否成功
set -uo pipefail
NS=blueking

echo "===== 1. 所有 Job（含 helm hook）====="
kubectl get jobs -n "$NS" --no-headers 2>/dev/null | awk '{printf "  %-50s %-10s %s\n", $1, $2, $3}'
echo "(空=没有组建集群的 Job)"

echo ""
echo "===== 2. 是否有完成的 pod（hook pod）====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -viE '^bk-elastic|^bk-etcd|^bk-mongodb|^bk-mysql8|^bk-rabbitmq|^bk-redis|^bk-zookeeper' | head -10
echo "(以上为非常规 Pod)"

echo ""
echo "===== 3. redis-cluster 相关 secret（密码）====="
kubectl get secret -n "$NS" 2>/dev/null | grep -i redis

echo ""
echo "===== 4. chart 默认副本与 cluster 配置 ====="
kubectl get statefulset bk-redis-cluster -n "$NS" -o jsonpath='{.spec.replicas}{\"\n\"}' 2>/dev/null
echo "--- 环境变量（含集群相关）---"
kubectl get statefulset bk-redis-cluster -n "$NS" -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\n\"}{end}' 2>/dev/null | grep -iE 'cluster|nodes|replicas|password|addr' | head -15

echo ""
echo "===== 5. helm release 状态（是否 hook 失败）====="
helm status bk-redis-cluster -n "$NS" 2>&1 | head -12

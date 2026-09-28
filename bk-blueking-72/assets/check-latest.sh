#!/usr/bin/env bash
# 用途：查看部署最新进展
set -uo pipefail
NS=blueking

echo "===== 1. Pod 就绪情况 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $1, $2, $3}'

echo ""
echo "===== 2. 就绪统计 ====="
total=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l)
ready=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c '1/1')
echo "就绪: $ready / $total"

echo ""
echo "===== 3. 仍未就绪的 Pod 状态原因 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -v '1/1' | while read -r name rest; do
  st=$(echo "$rest" | awk '{print $3}')
  echo "--- $name ($st) ---"
done

echo ""
echo "===== 4. 节点资源 ====="
kubectl top nodes 2>&1 | head -6

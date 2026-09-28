#!/usr/bin/env bash
# 用途：base-storage 验收 —— 确认是否真的全部就绪（不看 helm release，看 Pod/PVC 实际状态）
set -uo pipefail
NS=blueking

echo "===== 1. Pod 就绪总览 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{printf "  %-52s %-8s %s\n", $1, $2, $3}'

echo ""
total=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l)
ready=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -cE '([0-9]+)/\1' )
echo "  就绪: $ready / $total"

echo ""
echo "===== 2. PVC 状态（必须全 Bound）====="
kubectl get pvc -n "$NS" --no-headers 2>/dev/null | awk '{printf "  %-48s %-8s %s\n", $1, $2, $4}'
pc_total=$(kubectl get pvc -n "$NS" --no-headers 2>/dev/null | wc -l)
pc_bound=$(kubectl get pvc -n "$NS" --no-headers 2>/dev/null | grep -c Bound)
echo "  Bound: $pc_bound / $pc_total"

echo ""
echo "===== 3. 有状态副本是否都起来（StatefulSet）====="
kubectl get statefulset -n "$NS" --no-headers 2>/dev/null | awk '{printf "  %-48s %s\n", $1, $2}'

echo ""
echo "===== 4. 服务端口（验证存储层对外可用）====="
kubectl get svc -n "$NS" --no-headers 2>/dev/null | awk '{printf "  %-46s %-14s %s\n", $1, $2, $5}'

echo ""
echo "===== 5. 节点资源占用 ====="
kubectl top nodes 2>/dev/null | head -6

#!/usr/bin/env bash
# 用途：查看 base-storage 部署后的 Pod / PVC 状态
set -uo pipefail

echo "===== 1. helm release 列表 ====="
export KUBECONFIG=${KUBECONFIG:-/root/.kube/config}
helm list -n blueking 2>&1 | head -15

echo ""
echo "===== 2. Pod 状态 ====="
kubectl get pods -n blueking -o wide 2>&1 | head -25

echo ""
echo "===== 3. PVC 状态 ====="
kubectl get pvc -n blueking 2>&1 | head -20

echo ""
echo "===== 4. 未就绪 Pod 详情（事件）====="
kubectl get events -n blueking --sort-by=.lastTimestamp 2>&1 | tail -25

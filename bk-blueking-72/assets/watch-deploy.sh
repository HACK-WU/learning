#!/usr/bin/env bash
# 用途：查看 base-storage 部署结果
set -uo pipefail

echo "===== 1. helm release ====="
helm list -n blueking 2>&1 | head -15

echo ""
echo "===== 2. Pod 状态 ====="
kubectl get pods -n blueking 2>&1 | head -25

echo ""
echo "===== 3. 资源占用 ====="
kubectl top pods -n blueking 2>&1 | head -15

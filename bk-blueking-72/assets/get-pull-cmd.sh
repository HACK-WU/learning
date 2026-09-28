#!/usr/bin/env bash
# 用途：查出卡住的 Pod 用的完整镜像名 + 集群类型，用于给出准确的拉取命令
set -uo pipefail
NS=blueking

echo "===== 1. 所有未就绪 Pod 及其镜像 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -v '1/1' | awk '{print $1}' | while read -r p; do
  img=$(kubectl get pod "$p" -n "$NS" -o jsonpath='{.status.containerStatuses[0].image}' 2>/dev/null)
  st=$(kubectl get pod "$p" -n "$NS" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
  node=$(kubectl get pod "$p" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
  echo "$p"
  echo "   状态: ${st:-Running/其他}"
  echo "   镜像: $img"
  echo "   节点: $node"
done

echo ""
echo "===== 2. 节点列表（判断是否 kind：节点名带 control-plane/worker 且是容器）====="
kubectl get nodes -o wide --no-headers 2>/dev/null | awk '{print $1, $2, $6}'

echo ""
echo "===== 3. 节点是否为 docker 容器（kind 特征）====="
docker ps --format '{{.Names}}' 2>/dev/null | head -10

#!/usr/bin/env bash
# 用途：诊断 ImagePullBackOff 根因
set -uo pipefail
NS=blueking
POD=bk-elastic-elasticsearch-coordinating-only-0

echo "===== 1. 拉取失败原文 ====="
kubectl get events -n "$NS" --field-selector involvedObject.name="$POD" --sort-by=.lastTimestamp 2>&1 | grep -iE 'pull|back' | tail -6

echo ""
echo "===== 2. Pod 描述的 Events ====="
kubectl describe pod "$POD" -n "$NS" 2>&1 | grep -A8 'Events:' | tail -10

echo ""
echo "===== 3. 卡在哪个镜像 ====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.containerStatuses[*].image}{"\n"}{.status.initContainerStatuses[*].image}{"\n"}' 2>&1

echo ""
echo "===== 4. 该镜像在节点是否存在 ====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.nodeName}{"\n"}' 2>&1

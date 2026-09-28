#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. 两个目标镜像是否已就位 ====="
echo "  worker2 gateway:    $(docker exec k8s-c1-calico-worker2 ctr -n k8s.io images list 2>/dev/null | grep -c 'bkrepo-gateway:v3.3.1')"
echo "  worker  repository: $(docker exec k8s-c1-calico-worker  ctr -n k8s.io images list 2>/dev/null | grep -c 'bkrepo-repository:v3.3.1')"

echo ""
echo "===== 2. Pod 状态总览 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn

echo ""
echo "===== 3. 仍 ImagePullBackOff 的 Pod ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'ImagePull|ErrImage' | awk '{print "  "$1}'

echo ""
echo "===== 4. bkrepo / bkauth / apigateway Pod 明细 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'bkrepo|bkauth|apigw' | awk '{printf "  %-52s %s\n", $1, $3}'

echo ""
echo "===== 5. 节点镜像数 ====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  $n: $(docker exec $n ctr -n k8s.io images list 2>/dev/null | wc -l)"
done

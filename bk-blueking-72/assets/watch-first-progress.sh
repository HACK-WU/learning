#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. seq=first 相关 Pod ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'bkrepo|bkauth|apigw|bk-repo|bk-auth' | awk '{printf "  %-52s %-6s %s\n", $1, $2, $3}'

echo ""
echo "===== 2. 全部 Pod 按状态分组 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn

echo ""
echo "===== 3. 镜像拉取中的 Pod ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'ImagePull|ErrImage' | head -8

echo ""
echo "===== 4. 各节点新拉取的镜像数（判断进展）====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  $n: $(docker exec $n ctr -n k8s.io images list 2>/dev/null | wc -l)"
done

echo ""
echo "===== 5. release 状态 ====="
helm list -n "$NS" --no-headers 2>/dev/null | grep -iE 'repo|auth|apigw' | awk '{print "  "$1"  "$8}'

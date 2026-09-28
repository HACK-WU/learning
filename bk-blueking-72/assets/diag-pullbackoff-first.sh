#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. 两个 ImagePullBackOff Pod 的镜像 ====="
for p in bk-repo-bkrepo-gateway-6b7b95bf64-z6t86 bk-repo-bkrepo-repository-f55db8455-c9866; do
  img=$(kubectl get pod $p -n $NS -o jsonpath='{.spec.containers[0].image}')
  node=$(kubectl get pod $p -n $NS -o jsonpath='{.spec.nodeName}')
  echo "  $p"
  echo "    镜像: $img"
  echo "    节点: $node"
done

echo ""
echo "===== 2. 拉取失败原因（事件）====="
kubectl describe pod bk-repo-bkrepo-gateway-6b7b95bf64-z6t86 -n $NS 2>/dev/null | grep -A6 'Events:' | tail -8

echo ""
echo "===== 3. 该镜像是否已存在于节点 ====="
IMG=$(kubectl get pod bk-repo-bkrepo-gateway-6b7b95bf64-z6t86 -n $NS -o jsonpath='{.spec.containers[0].image}')
docker exec k8s-c1-calico-worker ctr -n k8s.io images list 2>/dev/null | grep -i 'gateway' | head -3 || echo "  节点上无此镜像"

echo ""
echo "===== 4. 其他 bkrepo Pod 用的镜像（对比，判断是否同一 registry）====="
kubectl get pods -n $NS -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null | grep -i 'bkrepo' | sort -u | head -10

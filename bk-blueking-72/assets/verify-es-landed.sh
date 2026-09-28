#!/usr/bin/env bash
# 核心问题：用户贴的 saved 日志，镜像到底落在哪？
# 三种可能：①kind 节点内 ②WSL 宿主机 containerd ③别处
set -uo pipefail
echo "########## A. WSL 宿主机 containerd ##########"
if command -v ctr >/dev/null 2>&1; then
  echo "  宿主机有 ctr，检查 k8s.io 与 default 命名空间："
  ctr -n k8s.io images list 2>/dev/null | grep -i elasticsearch | head -5 || echo "    k8s.io: 无"
  ctr -n default images list 2>/dev/null | grep -i elasticsearch | head -5 || echo "    default: 无"
else
  echo "  宿主机无 ctr"
fi

echo ""
echo "########## B. WSL 宿主机 docker ##########"
docker images 2>/dev/null | grep -i elasticsearch | head -5 || echo "  宿主机 docker: 无"

echo ""
echo "########## C. 三个 kind 节点内 ##########"
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  out=$(docker exec "$n" ctr -n k8s.io images list 2>/dev/null | grep -i 'bitnami/elasticsearch')
  if [ -n "$out" ]; then
    echo "  ✅ $n 有 ES 镜像:"
    echo "$out" | sed 's/^/     /'
  else
    echo "  ❌ $n 无 ES 镜像"
  fi
done

echo ""
echo "########## D. ES / zk Pod 实时状态 ##########"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'elastic|zookeeper' | awk '{print "  "$1"  "$2"  "$3}'

echo ""
echo "########## E. 各节点镜像总数变化（对照之前 93/152/153）##########"
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  c=$(docker exec "$n" ctr -n k8s.io images list 2>/dev/null | wc -l)
  echo "  $n: $c"
done

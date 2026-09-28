#!/usr/bin/env bash
set -uo pipefail
N=k8s-c1-calico-worker2
echo "===== 1. worker2 上 ES 镜像是否已存在 ====="
docker exec "$N" ctr -n k8s.io images list 2>/dev/null | grep -i elasticsearch || echo "  仍未找到"

echo ""
echo "===== 2. ES / etcd / zk Pod 当前状态 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'elastic|etcd|zookeeper' | awk '{print "  "$1"  "$2"  "$3}'

echo ""
echo "===== 3. 未就绪 Pod 的最近事件 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -v '1/1' | awk '{print $1}' | head -4 | while read -r p; do
  echo "  --- $p ---"
  kubectl describe pod "$p" -n blueking 2>/dev/null | grep -A3 'Events:' | tail -4
done

echo ""
echo "===== 4. 各节点镜像缓存数（判断还需拉多少）====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  c=$(docker exec "$n" ctr -n k8s.io images list 2>/dev/null | wc -l)
  echo "  $n: $c"
done

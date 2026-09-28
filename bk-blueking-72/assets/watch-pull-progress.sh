#!/usr/bin/env bash
set -uo pipefail
echo "===== worker 节点上目标镜像是否已就位 ====="
for img in bkrepo-helm bkrepo-opdata bkrepo-pypi bkrepo-repository; do
  c=$(docker exec k8s-c1-calico-worker ctr -n k8s.io images list 2>/dev/null | grep -c "$img:v3.3.1")
  echo "  worker   $img: $c"
done
for img in bkrepo-auth; do
  c=$(docker exec k8s-c1-calico-worker2 ctr -n k8s.io images list 2>/dev/null | grep -c "$img:v3.3.1")
  echo "  worker2  $img: $c"
done

echo ""
echo "===== content store 增长（判断是否在下载）====="
for n in k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  $n: $(docker exec $n du -sh /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null | awk '{print $1}')"
done

echo ""
echo "===== 当前 ImagePullBackOff ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -c 'ImagePullBackOff'

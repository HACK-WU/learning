#!/usr/bin/env bash
set -uo pipefail
echo "===== 各节点已就位的 second 批镜像 ====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  --- $n ---"
  docker exec $n ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -E 'bkiam|bkssm|bk-console-v1|sql-migrate|k8s-wait-for|busybox:1.34' | sed 's/^/    /'
done

echo ""
echo "===== 实时速率（10s采样）====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  s1=$(docker exec $n du -sb /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null | awk '{print $1}')
  sleep 10
  s2=$(docker exec $n du -sb /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null | awk '{print $1}')
  echo "  $n: $(( (s2-s1)/1024/10 )) KiB/s"
done

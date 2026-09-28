#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. 节点内 ctr pull 进程 ====="
for n in k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  --- $n ---"
  docker exec $n ps aux 2>/dev/null | grep -c '[c]tr -n k8s.io images pull' | xargs echo "    ctr pull 进程数:"
done

echo ""
echo "===== 2. content store 两次采样（间隔10s，算实时速率）====="
for n in k8s-c1-calico-worker k8s-c1-calico-worker2; do
  s1=$(docker exec $n du -sb /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null | awk '{print $1}')
  sleep 10
  s2=$(docker exec $n du -sb /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null | awk '{print $1}')
  delta=$((s2-s1))
  echo "  $n: 10秒增长 $((delta/1024/1024)) MiB  ≈ $((delta/1024/10)) KiB/s"
done

echo ""
echo "===== 3. 正在写入的 blob 文件（看谁在下）====="
docker exec k8s-c1-calico-worker sh -c 'find /var/lib/containerd/io.containerd.content.v1.content/blobs/sha256 -type f -newermt "-3 minutes" -printf "%s %p\n" 2>/dev/null | sort -rn | head -5' | awk '{printf "  %.1f MiB  %s\n", $1/1048576, substr($2,1,20)}'

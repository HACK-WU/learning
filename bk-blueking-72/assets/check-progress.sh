#!/usr/bin/env bash
set -uo pipefail
echo "清单镜像数: $(wc -l < /tmp/imgs-third.txt 2>/dev/null || echo '清单丢失')"
echo "日志行数: $(wc -l < /tmp/pull-third.log 2>/dev/null || echo 0)"
echo ""
echo "===== 日志尾部 ====="
tail -15 /tmp/pull-third.log 2>/dev/null || echo "  无日志"
echo ""
echo "===== 节点镜像增长（10s采样）====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  s1=$(docker exec $n du -sb /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null | awk '{print $1}')
  sleep 10
  s2=$(docker exec $n du -sb /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null | awk '{print $1}')
  echo "  $n: $(( (s2-s1)/1024/10 )) KiB/s  (总量 $(( s2/1024/1024/1024 ))G)"
done

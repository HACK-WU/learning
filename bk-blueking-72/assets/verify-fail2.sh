#!/usr/bin/env bash
set -uo pipefail
N=k8s-c1-calico-worker
echo "===== 1. 这两个镜像在 ctr 里到底有没有 ====="
for i in hub.bktencent.com/beats/filebeat:7.7.1 hub.bktencent.com/blueking/bk-gse-apimgr:v2.1.6-beta.65; do
  docker exec $N ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -qxF "$i" \
    && echo "  ✅ $i 已存在" || echo "  ❌ $i 不存在"
done

echo ""
echo "===== 2. 手动单次拉取 filebeat，看真实错误 ====="
docker exec $N ctr -n k8s.io images pull hub.bktencent.com/beats/filebeat:7.7.1 2>&1 | tail -6

echo ""
echo "===== 3. 对比：换一个已知能拉的 blueking 镜像 ====="
docker exec $N ctr -n k8s.io images pull hub.bktencent.com/library/busybox:1.34.0 2>&1 | tail -3

#!/usr/bin/env bash
# 核验：重试点"失败"是真失败还是脚本误判
set -uo pipefail

echo "===== 1. worker2 上 bkrepo-gateway 镜像到底在不在 ====="
docker exec k8s-c1-calico-worker2 ctr -n k8s.io images list 2>/dev/null | grep 'bkrepo-gateway' || echo "  ❌ 不存在"

echo ""
echo "===== 2. 用 content store 看已下载的 blob（判断进度）====="
docker exec k8s-c1-calico-worker2 sh -c 'du -sh /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null' || echo "  无法统计"

echo ""
echo "===== 3. 关键：直接再拉一次看真实输出（不截断）====="
timeout 60 docker exec k8s-c1-calico-worker2 ctr -n k8s.io images pull hub.bktencent.com/blueking/bkrepo-gateway:v3.3.1-beta.1 2>&1 | tail -20
echo "  退出码: $?"

echo ""
echo "===== 4. 再查镜像是否存在 ====="
docker exec k8s-c1-calico-worker2 ctr -n k8s.io images list 2>/dev/null | grep -c 'bkrepo-gateway' | xargs echo "  匹配行数:"
docker exec k8s-c1-calico-worker2 ctr -n k8s.io images list 2>/dev/null | grep 'bkrepo-gateway'

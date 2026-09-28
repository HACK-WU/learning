#!/usr/bin/env bash
# 串行 + 重试 拉取两个失败的大镜像（connection reset by peer）
# 目标节点由 Pod 调度决定
set -uo pipefail

pull_with_retry() {
  local node=$1 img=$2 max=${3:-5}
  for i in $(seq 1 $max); do
    echo "  [$node] 第 $i 次: $img"
    if docker exec "$node" ctr -n k8s.io images pull "$img" 2>&1 | tail -2; then
      if docker exec "$node" ctr -n k8s.io images list 2>/dev/null | grep -q "$(echo $img | sed 's/.*\///')"; then
        echo "  ✅ 成功 (第 $i 次)"
        return 0
      fi
    fi
    echo "  ⚠️ 失败，等待 10s 重试"
    sleep 10
  done
  echo "  ❌ $max 次均失败"
  return 1
}

echo "===== 1. bkrepo-gateway → worker2 ====="
pull_with_retry k8s-c1-calico-worker2 hub.bktencent.com/blueking/bkrepo-gateway:v3.3.1-beta.1 5

echo ""
echo "===== 2. bkrepo-repository → worker ====="
pull_with_retry k8s-c1-calico-worker hub.bktencent.com/blueking/bkrepo-repository:v3.3.1-beta.1 5

echo ""
echo "===== 3. 验证 ====="
docker exec k8s-c1-calico-worker2 ctr -n k8s.io images list 2>/dev/null | grep 'bkrepo-gateway' | head -1
docker exec k8s-c1-calico-worker ctr -n k8s.io images list 2>/dev/null | grep 'bkrepo-repository' | head -1

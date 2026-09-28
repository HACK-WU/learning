#!/usr/bin/env bash
# 补拉剩余缺失镜像（串行、充分重试）
set -uo pipefail
echo "开始: $(date +%H:%M:%S)"
echo ""

# control-plane 缺 bkiam + bkssm
# worker2 缺 bkssm
pull() {
  local n=$1 img=$2
  echo "  >>> [$n] $img"
  for i in 1 2 3 4 5; do
    if docker exec "$n" ctr -n k8s.io images pull "$img" >/dev/null 2>&1; then
      echo "      ✅ 成功（第 $i 次）"; return 0
    fi
    echo "      第 $i 次失败，等待重试..."
    sleep 5
  done
  echo "      ❌ 5 次均失败"; return 1
}

pull k8s-c1-calico-control-plane hub.bktencent.com/blueking/bkiam:v1.12.21
pull k8s-c1-calico-control-plane hub.bktencent.com/blueking/bkssm:v1.0.12
pull k8s-c1-calico-worker2      hub.bktencent.com/blueking/bkssm:v1.0.12

echo ""
echo "结束: $(date +%H:%M:%S)"
echo ""
echo "===== 最终核验：三节点 second 批镜像 ====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  --- $n ---"
  docker exec $n ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -vE '@sha256' | sort -u > /tmp/f-$n.txt
  while read -r img; do
    img=$(echo "$img" | tr -d '\r')
    grep -qx "$img" /tmp/f-$n.txt && echo "    ✅ $img" || echo "    ❌ $img"
  done < /tmp/imgs-second.txt
done

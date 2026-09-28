#!/usr/bin/env bash
# 预取：渲染指定 seq，提取镜像，拉到所有节点
# 用法: prefetch-images.sh <seq>
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
SEQ=${1:-second}
cd "$B" || exit 1

echo "===== 1. 渲染 seq=$SEQ 提取镜像 ====="
$HF -f base-blueking.yaml.gotmpl -l seq=$SEQ template 2>/dev/null \
  | grep -oE 'image: "?[^ "]+' | sed -E 's/image: "?//' | tr -d '"' \
  | sort -u > /tmp/imgs-$SEQ.txt
echo "  镜像数: $(wc -l < /tmp/imgs-$SEQ.txt)"
cat /tmp/imgs-$SEQ.txt | sed 's/^/    /'

echo ""
echo "===== 2. 检查每个节点已有的镜像（跳过重复拉取）====="
NODES="k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2"
for n in $NODES; do
  docker exec $n ctr -n k8s.io images list 2>/dev/null | awk '{print $1}' | grep -v '@' | sort -u > /tmp/has-$n.txt
  echo "  $n 已有: $(wc -l < /tmp/has-$n.txt)"
done

echo ""
echo "===== 3. 各节点缺失的镜像 ====="
for n in $NODES; do
  miss=$(comm -23 /tmp/imgs-$SEQ.txt /tmp/has-$n.txt 2>/dev/null | wc -l)
  echo "  $n 缺失: $miss"
done

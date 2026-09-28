#!/usr/bin/env bash
# 用途：诊断为什么镜像拉取慢导致 helm --wait 超时
set -uo pipefail
NS=blueking

echo "===== 1. 正在拉取的镜像（看谁卡住）====="
kubectl get events -n "$NS" --sort-by=.lastTimestamp 2>&1 | grep -iE 'pulling|pulled' | tail -15

echo ""
echo "===== 2. 镜像大小 vs 拉取耗时 ====="
kubectl get events -n "$NS" 2>&1 | grep -oE 'Successfully pulled image "[^"]*" in [0-9.]+[a-z]* \(.*Image size: [0-9]+' | tail -8

echo ""
echo "===== 3. 当前各节点已缓存的蓝鲸镜像数 ====="
for n in k8s-c1-calico-worker k8s-c1-calico-worker2 k8s-c1-calico-control-plane; do
  cnt=$(docker exec "$n" ctr -n k8s.io images list 2>/dev/null | grep -c 'bktencent' || echo "?")
  echo "$n: $cnt 个 bktencent 镜像"
done

echo ""
echo "===== 4. 网络测速：registry 下载速度 ====="
time curl -s -o /dev/null -w "速度: %{speed_download} B/s  耗时: %{time_total}s\n" \
  "https://hub.bktencent.com/v2/" 2>&1 | head -3

echo ""
echo "===== 5. helmfile defaults 的 timeout 设置 ====="
grep -nA10 'helmDefaults' /root/bk72/install/blueking/defaults.yaml | grep -E 'timeout|wait'

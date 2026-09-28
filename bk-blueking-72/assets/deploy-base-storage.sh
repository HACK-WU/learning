#!/usr/bin/env bash
# 用途：部署 base-storage（8 个存储组件）
# 已确认：内存 3.06Gi / PVC 160Gi / SC=standard(default) / 磁盘 705G
set -uo pipefail
B=/root/bk72/install/blueking
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
export PATH="$BIN:$PATH"
export HELM_CACHE_HOME=/root/bk72/.cache/helm
export HELM_CONFIG_HOME=/root/bk72/.config/helm
export HELM_DATA_HOME=/root/bk72/.local/share/helm

cd "$B" || exit 1

echo "===== 1. 创建 blueking 命名空间 ====="
kubectl create namespace blueking --dry-run=client -o yaml | kubectl apply -f -
kubectl get ns blueking

echo ""
echo "===== 2. 开始部署 base-storage ====="
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
timeout 3000 "$HF" -f base-storage.yaml.gotmpl apply --skip-diff-on-install 2>&1 | tail -60
echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "退出码: ${PIPESTATUS[0]}"

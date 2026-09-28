#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
cd "$B" || exit 1

echo "===== 1. 确认 seq=second 的 release ====="
$HF -f base-blueking.yaml.gotmpl -l seq=second list 2>&1 | grep -vE 'skipping|Adding|WARNING'

echo ""
echo "===== 2. 开始部署（timeout 已改为 1800）====="
echo "开始: $(date +%H:%M:%S)"
$HF -f base-blueking.yaml.gotmpl -l seq=second sync 2>&1 | tail -40
echo "结束: $(date +%H:%M:%S)"

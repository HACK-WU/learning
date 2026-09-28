#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
cd "$B" || exit 1

echo "===== seq=third release 清单 ====="
$HF -f base-blueking.yaml.gotmpl -l seq=third list 2>&1 | grep -vE 'skipping|Adding'

echo ""
echo "===== 开始部署 ====="
echo "开始: $(date +%H:%M:%S)"
$HF -f base-blueking.yaml.gotmpl -l seq=third sync 2>&1 | tail -45
echo "结束: $(date +%H:%M:%S)"

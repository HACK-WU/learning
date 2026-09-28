#!/usr/bin/env bash
# 部署 seq=first（最终版）
# 已核实：selector 生效，仅 3 个 release（bk-repo/bk-auth/bk-apigateway）
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
LOG=/tmp/bk-first-final-$(date +%H%M%S).log

cd "$B" || exit 1

echo "helmfile: $($HF version)"
echo "日志: $LOG"
echo "开始: $(date '+%H:%M:%S')"

echo ""
echo "===== 部署前确认：本次将部署的 release ====="
$HF -f base-blueking.yaml.gotmpl -l seq=first list 2>/dev/null | awk 'NR>1{print "  "$1}'

echo ""
echo "===== 执行 apply ====="
$HF -f base-blueking.yaml.gotmpl -l seq=first apply \
  --suppress-diff \
  --args="--timeout=1800s" 2>&1 | tee "$LOG"

echo ""
echo "退出码: ${PIPESTATUS[0]}"
echo "结束: $(date '+%H:%M:%S')"

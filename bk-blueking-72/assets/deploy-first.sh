#!/usr/bin/env bash
# 部署 seq=first（bk-repo / bk-auth / bk-apigateway）
# 教训：600s 超时不够 → 加大 timeout；--atomic 会回滚，先不加
set -uo pipefail
B=/root/bk72/install/blueking
LOG=/tmp/bk-first-$(date +%H%M%S).log

HF=/root/bk72/install/bin/helmfile
export PATH=/root/bk72/install/bin:$PATH

echo "部署批次: seq=first (bk-repo, bk-auth, bk-apigateway)"
echo "helmfile: $HF 版本: $($HF version 2>&1 | head -1)"
echo "日志文件: $LOG"
echo "开始时间: $(date '+%H:%M:%S')"

cd "$B" || exit 1

# 先渲染（dry-run）确认无误
echo ""
echo "===== 1. 渲染校验 ====="
$HF -f base.yaml.gotmpl -l seq=first template 2>&1 | head -5
echo "  渲染退出码: $?"

echo ""
echo "===== 2. 开始部署（timeout 加大到 1800s）====="
$HF -f base.yaml.gotmpl -l seq=first apply \
  --timeout 1800s --suppress-diff 2>&1 | tee "$LOG"
echo "  部署退出码: ${PIPESTATUS[0]}"

echo ""
echo "结束时间: $(date '+%H:%M:%S')"

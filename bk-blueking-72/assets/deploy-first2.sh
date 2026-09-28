#!/usr/bin/env bash
# 部署 seq=first（修正版）
# 修正1: helmfile 无 --timeout，用 --args 透传给 helm
# 修正2: 渲染检查不接 head，避免 141 假失败
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
LOG=/tmp/bk-first-ok-$(date +%H%M%S).log

echo "helmfile: $($HF version 2>&1 | head -1)"
echo "日志: $LOG"
echo "开始: $(date '+%H:%M:%S')"

cd "$B" || exit 1

echo ""
echo "===== 1. 渲染校验（不截断，只看退出码）====="
$HF -f base.yaml.gotmpl -l seq=first template > /tmp/render-first.yaml 2>/tmp/render-err.txt
rc=$?
echo "  渲染退出码: $rc"
echo "  渲染输出行数: $(wc -l < /tmp/render-first.yaml)"
grep -iE '^Error|error:' /tmp/render-err.txt | head -3
if [ $rc -ne 0 ]; then
  echo "  ❌ 渲染失败，终止"; tail -20 /tmp/render-err.txt; exit 1
fi

echo ""
echo "===== 2. 部署（timeout 透传给 helm）====="
$HF -f base.yaml.gotmpl -l seq=first apply \
  --suppress-diff \
  --args="--timeout=1800s" 2>&1 | tee "$LOG"

echo ""
echo "退出码: ${PIPESTATUS[0]}"
echo "结束: $(date '+%H:%M:%S')"

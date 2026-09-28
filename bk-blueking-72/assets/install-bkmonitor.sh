#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking
cd "$BK" || exit 1
export HELMFILE=/root/bk72/install/bin/helmfile

echo "===== 安装 bk-monitor 监控后台 ====="
echo "开始: $(date '+%F %T')"

timeout 3000 $HELMFILE -f 04-bkmonitor.yaml.gotmpl sync 2>&1 | tail -50

echo ""
echo "结束: $(date '+%F %T')"
echo "helmsync exit=$?"

echo ""
echo "===== release 状态 ====="
helm list -A --short 2>/dev/null | grep -E '^bk-monitor$' | sed 's/^/  /'
helm status bk-monitor -n blueking --short 2>/dev/null | head -5 | sed 's/^/  /'

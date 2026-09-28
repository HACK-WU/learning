#!/usr/bin/env bash
set -uo pipefail

{
echo "===== 监控安装状态 $(date '+%F %T') ====="
tot=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -icE 'bk-monitor')
run=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor' | grep -cE 'Running|Completed')
echo "  监控 Pod: 总数=$tot 已就绪=$run"

echo ""
echo "--- migrate Pod ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | sed 's/^/  /'

echo ""
echo "--- migrate 最新日志尾部 ---"
P=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
[ -n "$P" ] && kubectl logs -n blueking "$P" -c on-migrate --tail=15 2>/dev/null | sed 's/^/  /'

echo ""
echo "--- 仍在 Init 的 Pod（等待 migrate）---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor' | grep 'Init:' | head -10 | sed 's/^/  /'

echo ""
echo "--- 异常 Pod ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor' | grep -vE 'Running|Completed|Init:' | head -10 | sed 's/^/  /' || echo "  (无)"

echo ""
echo "--- helm release ---"
helm list -A --short 2>/dev/null | grep -E '^bk-monitor' | sed 's/^/  /' || echo "  (release 尚未列出)"
} > /root/monitor-status.txt 2>&1
cat /root/monitor-status.txt

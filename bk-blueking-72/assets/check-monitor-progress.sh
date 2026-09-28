#!/usr/bin/env bash
set -uo pipefail

echo "===== 检查 bk-monitor 安装进度 ====="
echo "现在: $(date '+%F %T')"

echo ""
echo "--- release 是否存在 ---"
helm list -A --short 2>/dev/null | grep -E '^bk-monitor' | sed 's/^/  /' || echo "  (bk-monitor release 尚不存在)"

echo ""
echo "--- 监控相关 Pod ---"
kubectl get pods -n blueking --no-headers 2>/dev/null \
  | grep -iE 'monitor|bkmonitor' | head -40 | sed 's/^/  /'

echo ""
echo "--- 监控相关 Pod 统计 ---"
tot=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -icE 'monitor')
run=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'monitor' | grep -cE 'Running|Completed')
echo "  总数=$tot  已就绪=$run"

echo ""
echo "--- 非 Running 的监控 Pod（异常）---"
kubectl get pods -n blueking --no-headers 2>/dev/null \
  | grep -iE 'monitor' | grep -vE 'Running|Completed' | head -20 | sed 's/^/  /' || echo "  (无异常)"

echo ""
echo "--- 监控 PVC ---"
kubectl get pvc -n blueking --no-headers 2>/dev/null | grep -iE 'monitor|influx|kafka|consul' | head -10 | sed 's/^/  /'

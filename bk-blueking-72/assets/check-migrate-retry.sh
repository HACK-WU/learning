#!/usr/bin/env bash
set -uo pipefail

{
echo "===== 1. migrate Pod 最新状态 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'migrate' | sed 's/^/  /'

echo ""
echo "===== 2. 监控 Pod 整体进度 ====="
tot=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -icE 'bk-monitor')
run=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor' | grep -cE 'Running|Completed')
echo "  监控 Pod 总数=$tot  已就绪=$run"

echo ""
echo "===== 3. migrate 最新日志（看是否还 403）====="
P=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
echo "  pod=$P"
[ -n "$P" ] && kubectl logs -n blueking "$P" -c on-migrate --tail=20 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 4. 存储层状态（kafka/consul/influxdb 是否稳定）====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-kafka|bk-consul|bk-influxdb' | sed 's/^/  /'
} > /root/status-now.txt 2>&1
cat /root/status-now.txt

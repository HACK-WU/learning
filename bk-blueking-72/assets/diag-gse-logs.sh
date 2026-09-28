#!/usr/bin/env bash
set -uo pipefail

{
echo "===== 1. 网关核心服务日志（含 403 记录）====="
kubectl logs -n blueking deploy/bk-apigateway-core-api --tail=60 2>/dev/null \
  | grep -iE '403|streamto|monitor|denied|permission' | tail -25 | sed 's/^/  /'

echo ""
echo "===== 2. 网关最近全部日志（找 403 上下文）====="
kubectl logs -n blueking deploy/bk-apigateway-core-api --tail=40 2>/dev/null | tail -25 | sed 's/^/  /'

echo ""
echo "===== 3. GSE data 服务日志（add_streamto 最终处理方）====="
kubectl logs -n blueking deploy/bk-gse-data --tail=40 2>/dev/null | tail -25 | sed 's/^/  /'

echo ""
echo "===== 4. GSE admin 日志 ====="
kubectl logs -n blueking deploy/bk-gse-admin --tail=30 2>/dev/null | tail -20 | sed 's/^/  /'

echo ""
echo "===== 5. 重新触发 migrate 并抓即时日志 ====="
echo "  (先删除旧 job pod 让其重试，观察新报错)"
kubectl delete pod -n blueking bk-monitor-migrate-1-2htvr --force --grace-period=0 2>/dev/null | sed 's/^/  /'
sleep 25
kubectl logs -n blueking -l job-name=bk-monitor-migrate-1 -c on-migrate --tail=25 2>/dev/null | sed 's/^/  /'
} > /root/gse-logs.txt 2>&1
cat /root/gse-logs.txt

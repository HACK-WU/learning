#!/usr/bin/env bash
set -uo pipefail
IP=172.26.238.136
{
echo "===== 1. 节点管理页面 ====="
curl -s -o /dev/null -m 10 -w "  bknodeman.paas.example.com -> HTTP %{http_code}\n" -H "Host: bknodeman.paas.example.com" "http://$IP/" 2>&1

echo ""
echo "===== 2. 监控页面（web Pod 卡 Init，预期不通）====="
curl -s -o /dev/null -m 10 -w "  bkmonitor.paas.example.com -> HTTP %{http_code}\n" -H "Host: bkmonitor.paas.example.com" "http://$IP/" 2>&1

echo ""
echo "===== 3. 已装好的页面做对照（PaaS3）====="
curl -s -o /dev/null -m 10 -w "  bkpaas.paas.example.com -> HTTP %{http_code}\n" -H "Host: bkpaas.paas.example.com" "http://$IP/" 2>&1

echo ""
echo "===== 4. nodeman 后端健康检查 ====="
kubectl exec -n blueking deploy/bk-nodeman-backend-api -- curl -s -m 5 -o /dev/null -w "  backend -> HTTP %{http_code}\n" http://127.0.0.1/ 2>&1 | tail -2

echo ""
echo "===== 5. 监控 web Pod 状态（页面是否起来了）====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-web' | sed 's/^/  /'

echo ""
echo "===== 6. 监控 grafana 页面（已 Running，可访问）====="
kubectl get svc bk-monitor-grafana -n blueking --no-headers 2>/dev/null | sed 's/^/  /'
} > /root/verify-pages.txt 2>&1
cat /root/verify-pages.txt

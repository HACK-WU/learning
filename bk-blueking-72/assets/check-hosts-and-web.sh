#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. hosts 里有没有监控域名 ====="
grep -iE 'monitor' /etc/hosts 2>/dev/null | sed 's/^/  /' || echo "  (未找到 monitor 相关)"
echo "  --- hosts 里 blueking 相关全部条目 ---"
grep -iE 'paas\.example|bk' /etc/hosts 2>/dev/null | sed 's/^/  /' | head -30

echo ""
echo "===== 2. 已就绪的监控 Pod 是哪些（重点找页面）====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor' | grep -E 'Running|Completed' | sed 's/^/  /'

echo ""
echo "===== 3. 监控的 web / 前端组件是否存在 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor.*(web|frontend|desktop|paas)' | sed 's/^/  /'

echo ""
echo "===== 4. 监控相关 Service（页面访问入口）====="
kubectl get svc -n blueking --no-headers 2>/dev/null | grep -iE 'monitor' | sed 's/^/  /'

echo ""
echo "===== 5. 监控相关 Ingress ====="
kubectl get ingress -n blueking --no-headers 2>/dev/null | grep -iE 'monitor' | sed 's/^/  /' || echo "  (无 monitor ingress)"
echo "  --- 全部 ingress ---"
kubectl get ingress -n blueking --no-headers 2>/dev/null | head -20 | sed 's/^/  /'
} > /root/check-hosts-web.txt 2>&1
cat /root/check-hosts-web.txt

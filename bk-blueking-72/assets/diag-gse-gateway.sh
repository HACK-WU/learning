#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. apigateway 里注册了哪些网关（含 bk-gse?）====="
kubectl exec -n blueking deploy/bk-apigateway-dashboard -- python manage.py list_gateways 2>/dev/null | head -20 | sed 's/^/  /'
echo "  --- 用 SQL 查 ---"
kubectl exec -n blueking deploy/bk-apigateway-dashboard -- python manage.py shell -c "
from apigateway.core.models import Gateway
for g in Gateway.objects.all()[:30]: print(g.name, g.status)
" 2>/dev/null | head -30 | sed 's/^/  /'

echo ""
echo "===== 2. ESB 里 bk-gse 组件是否注册 ====="
kubectl exec -n blueking deploy/bk-apigateway-bk-esb -- python manage.py shell -c "
from esb.component_system.models import SystemChannel, ComponentSystem
for s in ComponentSystem.objects.all()[:20]: print(s.name)
" 2>/dev/null | head -25 | sed 's/^/  /'

echo ""
echo "===== 3. 查看 monitor 报错中的请求 URL 到底打到哪 ====="
kubectl get cm bk-monitor-monitor-env -n blueking -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' | grep -iE 'gse|bkapi|api' | head -20 | sed 's/^/  /'

echo ""
echo "===== 4. 查 monitor 的 settings 里 gse 的 host 配置 ====="
P=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-web' | grep -v beat | awk '{print $1}' | head -1)
echo "  web pod: $P"
kubectl exec -n blueking "$P" -- env 2>/dev/null | grep -iE 'GSE|BK_API' | head -15 | sed 's/^/  /' || echo "  (web pod 未就绪，无法 exec)"

echo ""
echo "===== 5. 用 migrate pod 的环境（已就绪的容器）查 ====="
kubectl exec -n blueking bk-monitor-migrate-1-2htvr -c db-migrate -- env 2>/dev/null | grep -iE 'GSE|BKAPI|BK_API' | head -15 | sed 's/^/  /'

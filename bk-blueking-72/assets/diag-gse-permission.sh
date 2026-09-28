#!/usr/bin/env bash
set -uo pipefail
D=deploy/bk-apigateway-dashboard

echo "===== 1. bk-gse 网关给哪些 app 授权了 ====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
g = Gateway.objects.filter(name='bk-gse').first()
print('gateway:', g.name if g else 'NOT FOUND')
if g:
    ps = AppGatewayPermission.objects.filter(gateway=g)
    print('授权数:', ps.count())
    for p in ps[:20]: print('  app_code=', p.app_code, ' expires=', p.expires)
" 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. bk_monitorv3 这个 app 存在吗 ====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
gs = Gateway.objects.all()
for g in gs:
    ps = AppGatewayPermission.objects.filter(gateway=g, app_code='bk_monitorv3')
    if ps.exists():
        print(g.name, '-> bk_monitorv3 已授权', ps.count())
" 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 3. bk-unify-query 的授权情况（对比，已知成功）====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
g = Gateway.objects.filter(name='bk-unify-query').first()
if g:
    for p in AppGatewayPermission.objects.filter(gateway=g)[:10]: print('  ', p.app_code)
" 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 4. 监控的 app_code 实际是什么（可能不是 bk_monitorv3）====="
kubectl get cm bk-monitor-monitor-env -n blueking -o yaml 2>/dev/null | grep -iE 'APP_CODE|app_code' | head -5 | sed 's/^/  /'
kubectl get secret -n blueking -o name 2>/dev/null | grep -i monitor | head -5 | sed 's/^/  /'

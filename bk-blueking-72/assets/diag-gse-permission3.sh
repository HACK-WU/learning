#!/usr/bin/env bash
set -uo pipefail
D=deploy/bk-apigateway-dashboard

{
echo "===== bk-gse 网关已授权的 app（字段 bk_app_code）====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
g = Gateway.objects.filter(name='bk-gse').first()
ps = AppGatewayPermission.objects.filter(gateway=g)
print('授权数:', ps.count())
for p in ps: print('  ', p.bk_app_code)
" 2>&1 | grep -v '^Defaulted'

echo ""
echo "===== 所有网关 x 被授权 app 清单 ====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
for g in Gateway.objects.all():
    codes = sorted(set(p.bk_app_code for p in AppGatewayPermission.objects.filter(gateway=g)))
    if codes: print(g.name, ':', ', '.join(codes))
" 2>&1 | grep -v '^Defaulted'

echo ""
echo "===== 结论性检查：bk_monitor 是否被授权访问 bk-gse ====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
g = Gateway.objects.filter(name='bk-gse').first()
for code in ['bk_monitor','bk_monitorv3']:
    n = AppGatewayPermission.objects.filter(gateway=g, bk_app_code=code).count()
    print(code, '->', '已授权' if n else '未授权 <<<< 这是 403 的原因')
" 2>&1 | grep -v '^Defaulted'
} > /root/gse-perm3.txt 2>&1
cat /root/gse-perm3.txt

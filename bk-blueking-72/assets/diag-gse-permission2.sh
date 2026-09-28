#!/usr/bin/env bash
set -uo pipefail
D=deploy/bk-apigateway-dashboard
OUT=/root/gse-perm-detail.txt

{
echo "===== bk-gse 网关已授权的 9 个 app ====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
g = Gateway.objects.filter(name='bk-gse').first()
ps = AppGatewayPermission.objects.filter(gateway=g)
for p in ps: print(p.app_code, '| expires:', p.expires)
" 2>&1

echo ""
echo "===== 所有网关 x 所有被授权 app 的清单 ====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway
from apigateway.apps.permission.models import AppGatewayPermission
for g in Gateway.objects.all():
    codes = [p.app_code for p in AppGatewayPermission.objects.filter(gateway=g)]
    if codes: print(g.name, ':', ', '.join(sorted(set(codes))))
" 2>&1

echo ""
echo "===== monitor 用的 app_code（从 secret/configmap 找）====="
kubectl get secret bk-monitor-grafana-admin -n blueking -o jsonpath='{.data}' 2>&1 | head -c 300
echo ""
kubectl get cm bk-monitor-monitor-env -n blueking -o jsonpath='{.data.*}' 2>&1 | grep -oE 'APP_CODE[^ ]*|bk_[a-z0-9_]+' | sort -u | head -20
} > "$OUT" 2>&1

cat "$OUT"

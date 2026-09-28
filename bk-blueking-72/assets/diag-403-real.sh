#!/usr/bin/env bash
set -uo pipefail
D=deploy/bk-apigateway-dashboard

{
echo "===== 1. 网关侧记录的 bk_monitorv3 密钥，与监控用的对比 ====="
echo "  --- 监控用的 appSecret (helm values) ---"
helm get values bk-monitor -n blueking 2>/dev/null | grep -iE 'appSecret' | head -3 | sed 's/^/    /'

echo "  --- 网关/数据库里 bk_monitorv3 的密钥 ---"
kubectl get secret -n blueking -o name 2>/dev/null | grep -iE 'monitorv3|monitor' | sed 's/^/    /'

echo ""
echo "===== 2. GSE 侧是否校验 app（查 gse 的 api 白名单表）====="
kubectl exec -n blueking deploy/bk-apigateway-core-api -- env 2>/dev/null | grep -iE 'BK_APP|APP_CODE' | head -5 | sed 's/^/  /'

echo ""
echo "===== 3. 关键：ESB 里 gse 组件是否启用（403 可能因组件未发布）====="
kubectl exec -n blueking deploy/bk-apigateway-bk-esb -- sh -c 'ls /app 2>/dev/null | head' 2>&1 | head -5 | sed 's/^/  /'

echo ""
echo "===== 4. 直接看 bk-gse 网关的资源里有没有 config_add_streamto ====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway, Resource
g = Gateway.objects.filter(name='bk-gse').first()
rs = Resource.objects.filter(gateway=g)
print('bk-gse 资源数:', rs.count())
for r in rs[:30]: print('  ', r.name, '| method:', r.method, '| path:', r.path)
" 2>&1 | grep -v '^Defaulted'

echo ""
echo "===== 5. 网关 stage/release 状态（未发布会 403）====="
kubectl exec -n blueking $D -- python manage.py shell -c "
from apigateway.core.models import Gateway, Stage, Release
for g in Gateway.objects.filter(name__in=['bk-gse','bk-unify-query']):
    print(g.name, 'is_public:', getattr(g,'is_public',None), 'status:', g.status)
    for s in Stage.objects.filter(gateway=g):
        rel = Release.objects.filter(gateway=g, stage=s).order_by('-id').first()
        print('   stage:', s.name, '| release:', rel.resource_version.display if rel and rel.resource_version else 'NONE')
" 2>&1 | grep -v '^Defaulted'
} > /root/diag-403-real.txt 2>&1
cat /root/diag-403-real.txt

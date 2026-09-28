#!/usr/bin/env bash
set -uo pipefail

{
echo "===== 1. bk-gse 网关的 stage 与 release 状态（修正字段）====="
kubectl exec -n blueking deploy/bk-apigateway-dashboard -- python manage.py shell -c "
from apigateway.core.models import Gateway, Stage, Release
for g in Gateway.objects.filter(name__in=['bk-gse','bk-unify-query','bkpaas3']):
    print('gateway:', g.name, 'status:', g.status, 'is_public:', g.is_public)
    for s in Stage.objects.filter(gateway=g):
        rel = Release.objects.filter(gateway=g, stage=s).order_by('-id').first()
        print('   stage:', s.name, '| has_release:', bool(rel))
" 2>&1 | grep -v '^Defaulted' | grep -v '^Traceback' | grep -vE '^  File|^\s+\w+\.|^command terminated'

echo ""
echo "===== 2. 监控 migrate 实际请求的 URL（从报错提取）====="
echo "  报错显示: 请求URL: config_add_streamto/"
echo "  网关资源名: add_streamto  path=/api/v2/data/add_streamto"
echo "  => 需确认 config_add_streamto 是否为 ESB 侧旧命名"

echo ""
echo "===== 3. ESB 中 gse 的 config_add_streamto 组件 ====="
kubectl exec -n blueking deploy/bk-apigateway-bk-esb -- python manage.py shell -c "
from esb.component_system.models import ComponentSystem, ESBChannel
for c in ESBChannel.objects.filter(component_system__name='gse')[:50]:
    print('  ', c.name, '->', c.path)
" 2>&1 | grep -v '^Defaulted' | grep -viE 'traceback|file |^\s+' | head -40

echo ""
echo "===== 4. 检查 bkComponentApiUrl 是否指向正确的网关地址 ====="
helm get values bk-monitor -n blueking 2>/dev/null | grep -iE 'bkComponentApiUrl|bkApiUrlTmpl|bkapi' | head -10 | sed 's/^/  /'

echo ""
echo "===== 5. 集群内 bkapi 域名能否解析 ====="
kubectl run dnschk --rm -i --restart=Never --image=busybox:1.36 -n blueking -- \
  nslookup bkapi.paas.example.com 2>&1 | tail -8 | sed 's/^/  /'
} > /root/diag-final.txt 2>&1
cat /root/diag-final.txt

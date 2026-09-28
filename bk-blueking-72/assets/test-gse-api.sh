#!/usr/bin/env bash
set -uo pipefail

{
echo "===== 1. 从集群内直接调 bkapi 的 bk-gse 网关 ====="
echo "  --- 不带认证 ---"
kubectl run t1 --rm -i --restart=Never --image=curlimages/curl:latest -n blueking -- \
  curl -s -m 15 -w "\nHTTP=%{http_code}\n" \
  "http://bkapi.paas.example.com/api/bk-gse/prod/api/v2/data/query_streamto" \
  -H "Content-Type: application/json" -d '{}' 2>&1 | tail -6 | sed 's/^/  /'

echo ""
echo "  --- 带 bk_monitorv3 凭据 ---"
kubectl run t2 --rm -i --restart=Never --image=curlimages/curl:latest -n blueking -- \
  curl -s -m 15 -w "\nHTTP=%{http_code}\n" \
  "http://bkapi.paas.example.com/api/bk-gse/prod/api/v2/data/add_streamto" \
  -H "Content-Type: application/json" \
  -H "X-Bk-App-Code: bk_monitorv3" \
  -H "X-Bk-App-Secret: 6ca8aca1-b22f-4320-a99c-602f43a6203d" \
  -d '{"metadata":{"plat_id":0},"stream_to":{"name":"test","qos":0,"data_set":"x"}}' 2>&1 | tail -8 | sed 's/^/  /'

echo ""
echo "===== 2. 对比：bk_cmdb 凭据调同一接口 ====="
kubectl run t3 --rm -i --restart=Never --image=curlimages/curl:latest -n blueking -- \
  curl -s -m 15 -w "\nHTTP=%{http_code}\n" \
  "http://bkapi.paas.example.com/api/bk-gse/prod/api/v2/data/add_streamto" \
  -H "Content-Type: application/json" \
  -H "X-Bk-App-Code: bk_cmdb" \
  -H "X-Bk-App-Secret: xxxx" \
  -d '{}' 2>&1 | tail -6 | sed 's/^/  /'

echo ""
echo "===== 3. 网关里 bk_monitorv3 的密钥是否与 helm 一致 ====="
echo "  helm 用的: 6ca8aca1-b22f-4320-a99c-602f43a6203d"
echo "  官方 app_secret.yaml: "
grep -A3 'bk_monitorv3' /root/bk72/install/blueking/environments/default/app_secret.yaml 2>/dev/null | head -5 | sed 's/^/    /'

echo ""
echo "===== 4. bk-gse 网关是否需要资源级授权 ====="
kubectl exec -n blueking deploy/bk-apigateway-dashboard -- python manage.py shell -c "
from apigateway.core.models import Gateway, Resource
from apigateway.apps.permission.models import AppResourcePermission
g = Gateway.objects.filter(name='bk-gse').first()
r = Resource.objects.filter(gateway=g, name='add_streamto').first()
print('resource add_streamto:', r.name if r else 'NOT FOUND')
if r:
    ps = AppResourcePermission.objects.filter(gateway=g, resource=r)
    print('资源级授权数:', ps.count())
    for p in ps[:10]: print('   ', p.bk_app_code)
" 2>&1 | grep -v '^Defaulted' | grep -viE 'traceback|^  file|^\s+\w+\.|^command'
} > /root/test-gse-api.txt 2>&1
cat /root/test-gse-api.txt

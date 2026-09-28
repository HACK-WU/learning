#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. api_ping 源码 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'grep -n "def api_ping" -A 15 /usr/local/lib/python3.11/site-packages/iam/contrib/iam_migration/utils/do_migrate.py' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 2. iam_host 变量怎么来的 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'grep -n "iam_host" /app/paasng/infras/iam/bkpaas_iam_migration/migrator.py | head -10' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 3. 用 python 打印实际 iam_host 值 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'cd /app && python -c "
import django, os
os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\",\"paasng.settings\")
django.setup()
from django.conf import settings
print(\"  BK_IAM_V3_INNER_URL =\", settings.BK_IAM_V3_INNER_URL)
print(\"  BK_IAM_URL          =\", settings.BK_IAM_URL)
print(\"  BK_IAM_SKIP         =\", getattr(settings,\"BK_IAM_SKIP\",None))
print(\"  BK_IAM_APIGATEWAY_URL =\", getattr(settings,\"BK_IAM_APIGATEWAY_URL\",None))
print(\"  APP_CODE =\", getattr(settings,\"BK_IAM_V3_APP_CODE\",None))
" 2>&1 | grep -viE "warning|deprecat"' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 4. 实测 api_ping 调用 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'cd /app && python -c "
import django, os
os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\",\"paasng.settings\")
django.setup()
from iam.contrib.iam_migration.utils.do_migrate import do_migrate
from django.conf import settings
h = settings.BK_IAM_V3_INNER_URL
print(\"  ping host:\", h)
try:
    ok, r = do_migrate.api_ping(h)
    print(\"  api_ping ok =\", ok, \" resp =\", str(r)[:200])
except Exception as e:
    print(\"  EXC:\", type(e).__name__, e)
" 2>&1 | grep -viE "warning|deprecat|InsecureKey"' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 5. 该域名根路径返回体 ====="
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 http://bkiam-api.paas.example.com/ping | head -c 200" 2>&1 | sed 's/^/    /'
echo ""
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 http://bkiam-web.blueking.svc.cluster.local/ping | head -c 200" 2>&1 | sed 's/^/    /'

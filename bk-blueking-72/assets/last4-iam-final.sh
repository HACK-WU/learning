#!/usr/bin/env bash
NS=blueking
W_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-worker' | awk '{print $1}' | head -1)

echo "=== 1. settings 走环境变量（镜像里是 config.default/prod，由 env 决定） ==="
kubectl get deploy -n $NS bkiam-saas-worker -o json | python3 -c "
import json,sys
d=json.load(sys.stdin); c=d['spec']['template']['spec']['containers'][0]
for e in (c.get('env') or []):
    if any(k in e['name'].upper() for k in ['SETTINGS','DJANGO','ENV','BK_ENV']):
        print('    %s = %s'%(e['name'], e.get('value')))
"
echo "    容器内 DJANGO_SETTINGS_MODULE 实际值:"
kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'env | grep -iE "DJANGO|BK_ENV|SETTINGS"' 2>&1 | sed 's/^/      /'

echo ""
echo "=== 2. 带正确 settings 再 inspect ==="
timeout 90 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && DJANGO_SETTINGS_MODULE=config.prod timeout 60 /opt/venv/bin/celery -A config inspect ping --timeout 25' 2>&1 | grep -viE 'deprecat|cryptography' | head -8 | sed 's/^/    /'

echo ""
echo "=== 3. 触发真实任务（正确 settings） ==="
timeout 120 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && DJANGO_SETTINGS_MODULE=config.prod timeout 90 /opt/venv/bin/python3 -c "
import django,os
os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\",\"config.prod\")
django.setup()
from backend.apps.organization.tasks import sync_organization
r=sync_organization.delay()
print(\"TASK_ID=\"+str(r.id))
"' 2>&1 | grep -viE 'deprecat|cryptography' | tail -4 | sed 's/^/    /'

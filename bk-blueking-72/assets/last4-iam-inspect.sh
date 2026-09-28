#!/usr/bin/env bash
NS=blueking
W_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-worker' | awk '{print $1}' | head -1)

echo "=== 1. celery inspect ping（正确参数：-A config，broker 走配置） ==="
timeout 90 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && timeout 60 /opt/venv/bin/celery -A config inspect ping --timeout 25' 2>&1 | head -15 | sed 's/^/    /'

echo ""
echo "=== 2. 查已注册任务数 ==="
timeout 90 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && timeout 60 /opt/venv/bin/celery -A config inspect registered --timeout 25' 2>&1 | grep -o 'backend\.[a-zA-Z0-9_.]*' | sort -u | wc -l | xargs echo "    注册任务数:"
timeout 90 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && timeout 60 /opt/venv/bin/celery -A config inspect registered --timeout 25' 2>&1 | grep -o 'backend\.[a-zA-Z0-9_.]*' | sort -u | head -5 | sed 's/^/      /'

echo ""
echo "=== 3. 触发一个真实任务：看队列流转 ==="
RAB=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bk-rabbitmq' | awk '{print $1}' | head -1)
echo "    触发前 bk_iam 队列:"
kubectl exec -n $NS $RAB -- rabbitmqctl list_queues -p bkiam name messages 2>/dev/null | tail -3 | sed 's/^/      /'

timeout 90 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && timeout 60 /opt/venv/bin/python3 -c "
import django,os
os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\",\"config.settings\")
django.setup()
from backend.apps.organization.tasks import sync_organization
r=sync_organization.delay()
print(\"TASK_ID=\"+str(r.id))
"' 2>&1 | tail -5 | sed 's/^/    /'

sleep 12
echo "    触发后 bk_iam 队列:"
kubectl exec -n $NS $RAB -- rabbitmqctl list_queues -p bkiam name messages 2>/dev/null | tail -3 | sed 's/^/      /'

echo ""
echo "=== 4. 连接数变化（证明真消费了） ==="
kubectl exec -n $NS $RAB -- rabbitmqctl list_connections -p bkiam name state 2>/dev/null | grep -c running | xargs echo "    bkiam vhost running 连接数:"

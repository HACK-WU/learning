#!/usr/bin/env bash
NS=blueking
W_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-worker' | awk '{print $1}' | head -1)

echo "=== 1. 启动脚本原文（确认 celery app 路径） ==="
kubectl exec -n $NS $W_IAM -c bkiam-saas -- cat /app/bin/start_celery.sh 2>&1 | sed 's/^/    /'

echo ""
echo "=== 2. settings 模块在哪 ==="
kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'ls /app/config/ 2>/dev/null' 2>&1 | head -8 | sed 's/^/    /'
kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'ls /app/ 2>/dev/null' 2>&1 | head -12 | sed 's/^/    /'

echo ""
echo "=== 3. 用 worker 自己的 app 名再 inspect（worker 日志里写的是 bkiam） ==="
timeout 90 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && timeout 60 /opt/venv/bin/celery -A bkiam inspect ping --timeout 25' 2>&1 | grep -v DeprecationWarning | grep -v 'from cryptography' | head -10 | sed 's/^/    /'

echo ""
echo "=== 4. 直接从 rabbitmq 侧看：bk_iam 队列有没有真实消费 ==="
RAB=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bk-rabbitmq' | awk '{print $1}' | head -1)
kubectl exec -n $NS $RAB -- rabbitmqctl list_consumers -p bkiam 2>&1 | head -8 | sed 's/^/    /'

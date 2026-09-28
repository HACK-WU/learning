#!/usr/bin/env bash
NS=blueking
echo "=== 1. bkiam 容器有没有设 PYTHONUNBUFFERED ==="
kubectl get deploy -n $NS bkiam-saas-worker -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
hit=[(e['name'],e.get('value')) for e in (c.get('env') or []) if 'PYTHON' in e['name'].upper()]
print('    PYTHON 相关 env:', hit if hit else '无（stdout 会被块缓冲！）')
"

echo ""
echo "=== 2. rabbitmq 侧：bkiam vhost 有没有真实连接 ==="
RAB=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bk-rabbitmq' | awk '{print $1}' | head -1)
echo "    rabbit pod: $RAB"
kubectl exec -n $NS $RAB -- rabbitmqctl list_vhosts 2>&1 | sed 's/^/    vhost: /'
echo "    --- bkiam vhost 的连接 ---"
kubectl exec -n $NS $RAB -- rabbitmqctl list_connections -p bkiam vhost user name peer_host state 2>&1 | head -10 | sed 's/^/    /'
echo "    --- bkiam vhost 的 channel ---"
kubectl exec -n $NS $RAB -- rabbitmqctl list_channels -p bkiam vhost user number 2>&1 | head -8 | sed 's/^/    /'
echo "    --- bk_iam 队列 ---"
kubectl exec -n $NS $RAB -- rabbitmqctl list_queues -p bkiam name messages consumers 2>&1 | head -10 | sed 's/^/    /'

echo ""
echo "=== 3. 用 celery inspect 直接问 worker 活没活 ==="
W_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-worker' | awk '{print $1}' | head -1)
timeout 60 kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'cd /app && /opt/venv/bin/celery -A config.celery_app inspect ping -b amqp://bkiam:bkiam@bk-rabbitmq:5672/bkiam --timeout 20' 2>&1 | head -12 | sed 's/^/    /'

echo ""
echo "=== 4. 进程是否存在（用 /proc，容器没 ps） ==="
kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'for p in /proc/[0-9]*; do [ -r $p/cmdline ] && tr "\0" " " < $p/cmdline 2>/dev/null | grep -q celery && echo "$(basename $p): $(tr "\0" " " < $p/cmdline | cut -c1-90)"; done' 2>&1 | head -6 | sed 's/^/    /'

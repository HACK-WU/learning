#!/usr/bin/env bash
NS=blueking
W_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-worker' | awk '{print $1}' | head -1)
RAB=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bk-rabbitmq' | awk '{print $1}' | head -1)

echo "=== 1. 队列当前状态 ==="
kubectl exec -n $NS $RAB -- rabbitmqctl list_queues -p bkiam name messages consumers 2>/dev/null | sed 's/^/    /'

echo ""
echo "=== 2. bkiam vhost 累计消息统计（published/consumed） ==="
kubectl exec -n $NS $RAB -- rabbitmqctl list_queues -p bkiam name messages message_stats.publish message_stats.deliver_get 2>/dev/null | sed 's/^/    /'

echo ""
echo "=== 3. worker 日志最新（看有没有 succeeded） ==="
kubectl logs -n $NS $W_IAM -c bkiam-saas --tail=15 2>&1 | grep -viE 'deprecat|cryptography' | sed 's/^/    /'

echo ""
echo "=== 4. DB 侧证据：看任务是否有落库痕迹 ==="
kubectl exec -n $NS bk-mysql8-0 -- mysql -uroot -pblueking -N -e "
SELECT 'bkiam 库表数' k, COUNT(*) v FROM information_schema.tables WHERE table_schema='bkiam_saas';
SELECT 'audit 事件数', COUNT(*) FROM bkiam_saas.audit_eventlog;
SELECT '用户数', COUNT(*) FROM bkiam_saas.backend_user;
" 2>/dev/null | sed 's/^/    /'

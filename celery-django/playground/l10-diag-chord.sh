#!/usr/bin/env bash
# 深度诊断：chord 为什么超时？逐层排查
set -u

PROJ=/mnt/d/projects/learning/celery-django/projects/电商订单履约系统/实现
PY=/tmp/l9venv/bin/python
CELERY=/tmp/l9venv/bin/celery

cleanup () {
  pkill -9 -f 'celery -A proj' > /dev/null 2>&1 || true
  sleep 2
  return 0
}

cd "$PROJ" || exit 1
export DJANGO_SETTINGS_MODULE=proj.settings
export CELERY_BROKER_URL="redis://localhost:6380/7"
export CELERY_RESULT_BACKEND="redis://localhost:6380/8"

cleanup
redis-cli -p 6380 -n 7 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 8 FLUSHDB > /dev/null 2>&1 || true
rm -f db.sqlite3 logs/*.log
"$PY" manage.py migrate > /dev/null 2>&1
mkdir -p logs

"$CELERY" -A proj worker -Q fast,slow,default -c 4 -l DEBUG \
    --logfile=logs/diag.log --pidfile=logs/diag.pid --detach 2>&1 | tail -2 || true
sleep 6

echo "=== 1. worker 在消费哪些队列？==="
"$CELERY" -A proj inspect active_queues 2>&1 | head -20

echo
echo "=== 2. 逐个测试子任务（不经 chord）==="
"$PY" - <<'PYEOF' 2>&1 | tail -25
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()

from orders.models import Order, Stock
from orders.tasks import issue_coupon, send_notification, write_reconciliation

stock, _ = Stock.objects.get_or_create(sku='SKU_D', defaults={'quantity': 5})
order = Order.objects.create(user_id=1, sku='SKU_D', status='PENDING')
Order.objects.filter(id=order.id).update(status='PAID')

print('--- 单独测 issue_coupon ---')
try:
    r = issue_coupon.delay(order.id)
    print('  结果:', r.get(timeout=15))
except Exception as e:
    print(f'  ❌ 失败 {type(e).__name__}: {str(e)[:200]}')

print('--- 单独测 send_notification ---')
try:
    r = send_notification.delay(order.id)
    print('  结果:', r.get(timeout=15))
except Exception as e:
    print(f'  ❌ 失败 {type(e).__name__}: {str(e)[:200]}')

print('--- 单独测 write_reconciliation（直接传结果列表）---')
try:
    r = write_reconciliation.delay(
        [{'coupon_issued': True, 'order_id': 1}, {'notified': True, 'order_id': 1}],
        order.id,
    )
    print('  结果:', r.get(timeout=15))
except Exception as e:
    print(f'  ❌ 失败 {type(e).__name__}: {str(e)[:200]}')
PYEOF

echo
echo "=== 3. 队列情况 ==="
for q in fast slow default celery; do
  echo "  $q = $(redis-cli -p 6380 -n 7 LLEN $q)"
done

echo
echo "=== 4. worker 日志中的任务痕迹 ==="
grep -iE 'Received task|succeeded|failed|ERROR|chord' logs/diag.log 2>/dev/null | tail -20 || echo "(无)"

cleanup
echo
echo "==============================================="
echo "诊断结束"
exit 0

#!/usr/bin/env bash
# 验证 chord 修复效果 + 抓取 chord 解算日志
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

"$CELERY" -A proj worker -Q fast,slow -c 4 -l DEBUG \
    --logfile=logs/fix.log --pidfile=logs/fix.pid --detach 2>&1 | tail -2 || true
sleep 6

echo "=== 1. 各任务的 ignore_result 配置 ==="
"$PY" - <<'PYEOF' 2>&1 | tail -10
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()
from proj.celery import app
for name in ['orders.tasks.issue_coupon', 'orders.tasks.send_notification',
             'orders.tasks.write_reconciliation', 'orders.tasks.close_order',
             'orders.tasks.scan_timeout_orders', 'orders.tasks.heartbeat']:
    t = app.tasks.get(name)
    if t:
        print(f'  {name:45s} ignore_result={t.ignore_result}')
PYEOF

echo
echo "=== 2. 跑 chord ==="
"$PY" - <<'PYEOF' 2>&1 | tail -15
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()

from orders.models import Order, Reconciliation, Stock
from orders.tasks import fulfill_order

stock, _ = Stock.objects.get_or_create(sku='SKU_FIX', defaults={'quantity': 5})
order = Order.objects.create(user_id=1, sku='SKU_FIX', status='PENDING')
Order.objects.filter(id=order.id).update(status='PAID')
print(f'订单 #{order.id}')

r = fulfill_order.delay(order.id)
try:
    res = r.get(timeout=35)
    print(f'✅ chord 完成: {res}')
except Exception as e:
    print(f'❌ chord 失败: {type(e).__name__}: {str(e)[:200]}')

recs = Reconciliation.objects.filter(order_id=order.id)
print(f'对账记录数 = {recs.count()}  ← 期望 1')
for rec in recs:
    print(f'  order={rec.order_id} coupon_ok={rec.coupon_ok} notify_ok={rec.notify_ok}')
PYEOF

echo
echo "=== 3. chord 解算日志（unlock / Chord）==="
grep -iE 'chord|unlock|callback' logs/fix.log 2>/dev/null | tail -15 || echo "(无 chord 日志)"

echo
echo "=== 4. 任务执行日志 ==="
grep -iE '\[task_start\]|\[task_end\]|succeeded' logs/celery.log 2>/dev/null | tail -12 || echo "(无)"

cleanup
echo
echo "==============================================="
echo "验证结束"
exit 0

#!/usr/bin/env bash
# chord 完成了，但对账记录没写入 → 查回调到底有没有执行
set -u

PROJ=/mnt/d/projects/learning/celery-django/projects/电商订单履约系统/实现
VENV=/mnt/d/projects/learning/celery-django/.venv
PY=$VENV/bin/python
CELERY=$VENV/bin/celery

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
    --logfile=logs/cb.log --pidfile=logs/cb.pid --detach 2>&1 | tail -1 || true
sleep 6

"$PY" - <<'PYEOF' 2>&1 | tail -20
import os, django, time
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()

from orders.models import Order, Reconciliation, Stock
from orders.tasks import fulfill_order

stock, _ = Stock.objects.get_or_create(sku='SKU_CB', defaults={'quantity': 5})
order = Order.objects.create(user_id=1, sku='SKU_CB', status='PENDING')
Order.objects.filter(id=order.id).update(status='PAID')

r = fulfill_order.delay(order.id)
print('chord id =', r.id)
try:
    print('chord 完成：', r.get(timeout=40))
except Exception as e:
    print(f'失败：{type(e).__name__}: {str(e)[:200]}')

time.sleep(3)   # 给回调留出落库时间
print('对账记录数 =', Reconciliation.objects.filter(order_id=order.id).count())
PYEOF

echo
echo "=== 回调任务 write_reconciliation 是否被调度？==="
grep -E 'write_reconciliation' logs/cb.log 2>/dev/null | tail -10 || echo "(日志里完全没有 write_reconciliation)"

echo
echo "=== 是否有报错 ==="
grep -iE 'ERROR|Traceback|Exception' logs/cb.log 2>/dev/null | tail -15 || echo "(无报错)"

cleanup
echo
echo "==============================================="
echo "诊断结束"
exit 0

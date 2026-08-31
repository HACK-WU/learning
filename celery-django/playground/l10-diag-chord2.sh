#!/usr/bin/env bash
# 深挖：default 队列里那 1 条消息到底是什么？
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

# 这次让 worker 也消费 default
"$CELERY" -A proj worker -Q fast,slow,default -c 4 -l DEBUG \
    --logfile=logs/diag.log --pidfile=logs/diag.pid --detach 2>&1 | tail -1 || true
sleep 6

"$PY" - <<'PYEOF' 2>&1 | tail -15
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()

from orders.models import Order, Stock
from orders.tasks import fulfill_order

stock, _ = Stock.objects.get_or_create(sku='SKU_D2', defaults={'quantity': 5})
order = Order.objects.create(user_id=1, sku='SKU_D2', status='PENDING')
Order.objects.filter(id=order.id).update(status='PAID')

r = fulfill_order.delay(order.id)
print('chord 提交，等待 40 秒（这次 worker 也消费 default）...')
try:
    print('chord 完成：', r.get(timeout=40))
except Exception as e:
    print(f'chord 失败：{type(e).__name__}: {str(e)[:200]}')
PYEOF

echo
echo "=== 队列 ==="
for q in fast slow default celery; do
  echo "  $q = $(redis-cli -p 6380 -n 7 LLEN $q)"
done

echo
echo "=== worker 日志里 chord 相关 ==="
grep -iE 'chord|unlock|Received task|succeeded|ERROR' logs/diag.log 2>/dev/null | tail -25 || echo "(无)"

cleanup
echo
echo "==============================================="
echo "诊断结束"
exit 0

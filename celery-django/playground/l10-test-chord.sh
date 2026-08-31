#!/usr/bin/env bash
# 验证 chord 编排 + 幂等关单在真实 worker 里能跑通
# 重点：① chord 回调能否触发 ② 依赖是否齐全 ③ 慢任务是否进 slow 队列
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

echo "#####################################################"
echo "# 步骤 0：检查依赖"
echo "#####################################################"
"$PY" -c "import requests; print('requests', requests.__version__)" 2>&1 | head -2

echo
echo "#####################################################"
echo "# 步骤 1：起 worker（消费 fast + slow）"
echo "#####################################################"
cleanup
redis-cli -p 6380 -n 7 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 8 FLUSHDB > /dev/null 2>&1 || true
rm -f db.sqlite3 logs/*.log
"$PY" manage.py migrate > /dev/null 2>&1

mkdir -p logs
# ⭐ worker 只消费 fast/slow：所有任务都靠 CELERY_TASK_ROUTES 显式路由
#    若这里 chord 跑不通，说明有任务漏配了路由 → 补路由，而不是让 worker 去消费 default
"$CELERY" -A proj worker -Q fast,slow -c 4 -l INFO \
    --logfile=logs/chord-worker.log --pidfile=logs/chord.pid --detach 2>&1 | tail -2 || true
sleep 6

echo "--- worker 在消费哪些队列 ---"
"$CELERY" -A proj inspect active_queues 2>&1 | grep -E 'name|fast|slow' | head -8

echo
echo "#####################################################"
echo "# 步骤 2：测试 chord 编排（发券 + 通知 并行 → 汇总对账）"
echo "#####################################################"
"$PY" - <<'PYEOF' 2>&1 | tail -20
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()

from orders.models import Order, Reconciliation, Stock
from orders.tasks import fulfill_order

stock, _ = Stock.objects.get_or_create(sku='SKU_CHORD', defaults={'quantity': 5})
order = Order.objects.create(user_id=1, sku='SKU_CHORD', quantity=1, status='PENDING')
Order.objects.filter(id=order.id).update(status='PAID')
print(f'创建已支付订单 #{order.id}')

r = fulfill_order.delay(order.id)
print('chord 已提交，等待 40 秒...')
try:
    res = r.get(timeout=40)
    print(f'chord 完成：{res}')
except Exception as e:
    print(f'chord 失败：{type(e).__name__}: {str(e)[:200]}')

# ⭐ chord 返回只代表"回调被调度"，不代表"回调已落库"
#    要给回调一点执行时间，否则会查到 0 条（实测踩过）
import time
time.sleep(3)

recs = Reconciliation.objects.filter(order_id=order.id)
print(f'对账记录数 = {recs.count()}  <- 期望 1')
for rec in recs:
    print(f'  order={rec.order_id} coupon_ok={rec.coupon_ok} notify_ok={rec.notify_ok}')
PYEOF

echo
echo "#####################################################"
echo "# 步骤 3：队列路由是否生效"
echo "#####################################################"
sleep 2
echo "  fast    = $(redis-cli -p 6380 -n 7 LLEN fast)"
echo "  slow    = $(redis-cli -p 6380 -n 7 LLEN slow)"
echo "  default = $(redis-cli -p 6380 -n 7 LLEN default)  <- 应为 0（都被路由走了）"

cleanup
echo
echo "==============================================="
echo "测试结束"
exit 0

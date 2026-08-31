#!/usr/bin/env bash
# 决定性验证：Phase 3 的结论（"chord 解锁任务走 default 队列"）是真的吗？
#
# 假设 A（Phase 3 结论）：chord 的解锁任务走 default → 不带 default 就挂死
# 假设 B（官方文档推论）：Redis backend 有原生 chord 协调（ZADD/ZCOUNT），
#                        不需要 chord_unlock 轮询；真正原因是 fulfill_order 漏配路由
#
# 判据：给 fulfill_order 补上路由后，worker 只消费 fast/slow（不含 default），
#       看 chord 能不能跑通。
#       跑得通 → A 错 B 对；跑不通 → A 对 B 错
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

# 备份配置
cp proj/settings_celery.py /tmp/settings_celery.py.bak

# 给 fulfill_order 补上路由（临时打补丁，不改源文件）
"$PY" - <<'PYEOF'
p = 'proj/settings_celery.py'
s = open(p, encoding='utf-8').read()
old = "    'orders.tasks.send_notification': {'queue': 'fast'},"
new = "    'orders.tasks.fulfill_order': {'queue': 'fast'},   # 临时补丁：验证用\n    'orders.tasks.send_notification': {'queue': 'fast'},"
assert old in s
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
print('已临时给 fulfill_order 补上路由')
PYEOF

cleanup
redis-cli -p 6380 -n 7 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 8 FLUSHDB > /dev/null 2>&1 || true
rm -f db.sqlite3 logs/*.log
"$PY" manage.py migrate > /dev/null 2>&1
mkdir -p logs

# ⭐ 关键：worker 只消费 fast/slow，不含 default
"$CELERY" -A proj worker -Q fast,slow -c 4 -l INFO \
    --logfile=logs/v.log --pidfile=logs/v.pid --detach 2>&1 | tail -1 || true
sleep 6

"$PY" - <<'PYEOF' 2>&1 | tail -10
import os, django, time
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()
from orders.models import Order, Reconciliation, Stock
from orders.tasks import fulfill_order
stock, _ = Stock.objects.get_or_create(sku='SKU_V', defaults={'quantity': 5})
order = Order.objects.create(user_id=1, sku='SKU_V', status='PENDING')
Order.objects.filter(id=order.id).update(status='PAID')
r = fulfill_order.delay(order.id)
try:
    print('chord 结果:', r.get(timeout=30))
except Exception as e:
    print(f'chord 失败: {type(e).__name__}')
time.sleep(3)
print('对账记录数 =', Reconciliation.objects.filter(order_id=order.id).count(), '(期望 1)')
PYEOF

echo
echo "=== 队列积压（关键：default 是否还有积压）==="
for q in fast slow default; do
  echo "  $q = $(redis-cli -p 6380 -n 7 LLEN $q)"
done

echo
echo "=== 日志里有没有 chord_unlock ==="
grep -ciE 'chord_unlock' logs/v.log 2>/dev/null || echo "0"

# 还原配置
cp /tmp/settings_celery.py.bak proj/settings_celery.py
echo "已还原配置"

cleanup
echo
echo "==============================================="
echo "判定实验结束"
exit 0

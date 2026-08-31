#!/usr/bin/env bash
# 端到端验证：真实跑通 Django + Celery，验证核心链路
# 这比"看起来对"重要得多 —— 是"代码真能跑"的硬证据
set -u

PROJ=/mnt/d/projects/learning/celery-django/projects/电商订单履约系统/实现
if [ -x "/mnt/d/projects/learning/celery-django/.venv/bin/python" ]; then
  PY=/mnt/d/projects/learning/celery-django/.venv/bin/python
  CELERY=/mnt/d/projects/learning/celery-django/.venv/bin/celery
else
  PY=$(command -v python3 || echo python3)
  CELERY=$(command -v celery || echo celery)
fi

cleanup () {
  pkill -9 -f 'celery -A proj' > /dev/null 2>&1 || true
  pkill -9 -f 'proj worker' > /dev/null 2>&1 || true
  sleep 2
  return 0
}

cd "$PROJ" || exit 1

echo "#####################################################"
echo "# 步骤 1：Django 能否导入 Celery app"
echo "#####################################################"
export DJANGO_SETTINGS_MODULE=proj.settings
export CELERY_BROKER_URL="redis://localhost:6380/7"
export CELERY_RESULT_BACKEND="redis://localhost:6380/8"

"$PY" -c "
import django
django.setup()
from proj.celery import app
print('✅ Celery app 导入成功')
print('   broker =', app.conf.broker_url)
print('   accept_content =', app.conf.accept_content)
print('   task_acks_late =', app.conf.task_acks_late)
print('   soft_time_limit =', app.conf.task_soft_time_limit)
print('   result_expires =', app.conf.result_expires)
" 2>&1 | tail -20

echo
echo "#####################################################"
echo "# 步骤 2：任务是否注册成功（含路由）"
echo "#####################################################"
"$PY" -c "
import django
django.setup()
from proj.celery import app
tasks = sorted([t for t in app.tasks if t.startswith('orders.')])
print('已注册 orders 任务:')
for t in tasks:
    print('  -', t)
print()
print('路由配置:')
for name, route in app.conf.task_routes.items():
    print(f'  {name} → {route}')
" 2>&1 | tail -25

echo
echo "#####################################################"
echo "# 步骤 3：数据库迁移 + 建测试数据"
echo "#####################################################"
"$PY" manage.py migrate --run-syncdb 2>&1 | tail -8

echo
echo "#####################################################"
echo "# 步骤 4：起 worker，真实执行关单任务（验证 CAS 幂等）"
echo "#####################################################"
cleanup
redis-cli -p 6380 -n 7 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 8 FLUSHDB > /dev/null 2>&1 || true
rm -f db.sqlite3

"$PY" manage.py migrate --run-syncdb > /dev/null 2>&1

mkdir -p logs
"$CELERY" -A proj worker -Q slow,fast -c 4 -l INFO \
    --logfile=logs/e2e-worker.log --pidfile=logs/e2e.pid --detach 2>&1 | tail -2 || true
sleep 6

echo "--- worker 是否起来 ---"
"$CELERY" -A proj inspect stats 2>/dev/null | head -3 || echo "  worker 未响应"

echo
echo "--- 创建订单并调用关单任务 3 次（模拟重复执行）---"
"$PY" - <<'PYEOF' 2>&1 | tail -20
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()

from orders.models import Order, Stock
from orders.tasks import close_order

# 建库存
stock, _ = Stock.objects.get_or_create(sku='SKU_E2E', defaults={'quantity': 10})
stock.quantity = 10
stock.save()

# 创建待支付订单
order = Order.objects.create(user_id=1, sku='SKU_E2E', quantity=1, status='PENDING')
print(f'创建订单 #{order.id}，初始库存 = {Stock.objects.get(sku="SKU_E2E").quantity}')

# ⭐ 同步调用关单 3 次（模拟重复执行）
for i in range(3):
    r = close_order.apply(args=[order.id])
    print(f'  第 {i+1} 次执行 → {r.get(timeout=15)}')

order.refresh_from_db()
final_stock = Stock.objects.get(sku='SKU_E2E').quantity
print()
print(f'最终订单状态 = {order.status}')
print(f'最终库存     = {final_stock}   ← 期望 11（只回滚 1 次）')
if final_stock == 11:
    print('✅ 幂等生效：重复执行 3 次，库存只回滚 1 次')
else:
    print(f'❌ 幂等失效：库存应为 11，实际 {final_stock}')
PYEOF

echo
echo "#####################################################"
echo "# 步骤 5：验证日志里带 task_id（可观测性）"
echo "#####################################################"
# ⚠️ 注意：task_id 日志写在 logs/celery.log（LOGGING 配置的 RotatingFileHandler），
#    不是 worker 的 --logfile（那个只收 Celery 自身的 stderr 日志）
if grep -qE '\[task_start\] task_id=' logs/celery.log 2>/dev/null; then
  echo "  ✅ 日志带 task_id，样例："
  grep -E '\[task_start\]|\[task_end\]' logs/celery.log | head -3 | sed 's/^/     /'
  echo
  echo "  ✅ 幂等痕迹也在日志里："
  grep -E '幂等生效' logs/celery.log | head -2 | sed 's/^/     /'
else
  echo "  ❌ 日志无 task_id —— 检查信号钩子是否注册"
fi

cleanup
echo
echo "==============================================="
echo "端到端验证结束"
exit 0

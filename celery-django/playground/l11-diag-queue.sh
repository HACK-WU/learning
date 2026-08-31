#!/usr/bin/env bash
# 关键取证：worker 只消费 fast/slow 时，default 队列里积压的到底是哪条任务？
# 官方说法（DeepWiki / celery 源码）：Redis backend 有原生 chord 协调，
#   用 ZADD/ZCOUNT 追踪，最后一个成员完成时直接 callback.apply_async()
#   celery.chord_unlock 只在「backend 无原生支持」时才作为兜底轮询任务出现
# 所以：那条消息真的是 chord_unlock 吗？必须看消息内容，不能猜。
set -u

PROJ=/mnt/d/projects/learning/celery-django/projects/电商订单履约系统/实现
VENV=/mnt/d/projects/learning/celery-django/.venv
PY=$VENV/bin/python
CELERY=$VENV/bin/celery
DB=7

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

"$CELERY" -A proj worker -Q fast,slow -c 4 -l INFO \
    --logfile=logs/q.log --pidfile=logs/q.pid --detach 2>&1 | tail -1 || true
sleep 6

"$PY" - <<'PYEOF' 2>&1 | tail -8
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')
django.setup()
from orders.models import Order, Stock
from orders.tasks import fulfill_order
stock, _ = Stock.objects.get_or_create(sku='SKU_Q', defaults={'quantity': 5})
order = Order.objects.create(user_id=1, sku='SKU_Q', status='PENDING')
Order.objects.filter(id=order.id).update(status='PAID')
r = fulfill_order.delay(order.id)
try:
    print('chord 结果:', r.get(timeout=25))
except Exception as e:
    print(f'chord 超时（预期）: {type(e).__name__}')
PYEOF

echo
echo "=== 各队列积压 ==="
for q in fast slow default celery unacked; do
  echo "  $q = $(redis-cli -p 6380 -n $DB LLEN $q)"
done

echo
echo "=== 积压消息的真实内容（解出 task 名）==="
"$PY" - <<'PYEOF'
import redis, json
r = redis.Redis(host='localhost', port=6380, db=7)
for q in ['fast', 'slow', 'default', 'celery']:
    n = r.llen(q)
    if n == 0:
        continue
    print(f'--- 队列 {q}（{n} 条）---')
    for i in range(n):
        raw = r.lindex(q, i)
        if not raw:
            continue
        try:
            env = json.loads(raw)
        except Exception as e:
            print(f'  [{i}] 非 JSON: {str(e)[:80]}')
            continue
        props = env.get('properties') or {}
        headers = env.get('headers') or {}
        task = props.get('task') or headers.get('task') or '(无 task 字段)'
        task_id = props.get('id') or headers.get('id')
        print(f'  [{i}] task = {task}')
        print(f'       id   = {task_id}')
        # chord_unlock 会有 chord 字段
        if 'chord' in (headers or {}):
            print(f'       chord = {headers["chord"]}')
        if 'group' in (headers or {}):
            print(f'       group = {headers["group"]}')
PYEOF

echo
echo "=== worker 日志里 chord 相关 ==="
grep -iE 'chord|unlock|Received task|succeeded' logs/q.log 2>/dev/null | tail -20 || echo "(无)"

cleanup
echo
echo "==============================================="
echo "取证结束"
exit 0

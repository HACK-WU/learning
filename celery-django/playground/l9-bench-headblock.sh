#!/usr/bin/env bash
# 实测 4：队头阻塞 —— 慢任务把快任务全堵在后面的真实证据
# 场景：先灌 20 个 slow_task(2s)，再投 5 个 fast_task，看快任务要等多久
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python

echo "##################################################"
echo "# 场景 A：全部堆在默认队列 celery（单 worker, -c 4）"
echo "##################################################"

redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 \
    --prefetch-multiplier=1 \
    --loglevel=WARNING --logfile=/tmp/l9-a.log --detach \
    --pidfile=/tmp/l9-worker.pid 2>&1 | tail -1
sleep 4

"$PY" - <<'PYEOF'
import time
from celery import group
from celeryapp import app

# ① 先灌 20 个慢任务（模拟跑批）
for i in range(20):
    app.send_task('l9.slow_task', args=[i], queue='celery')

# ② 立刻投 5 个快任务（模拟用户点按钮）
t0 = time.time()
fast = group(app.signature('l9.fast_task', args=[i]) for i in range(5))
res = fast.apply_async()
res.get(timeout=600)
el = time.time() - t0
print(f"RESULT_A 快任务等待耗时 = {el:.2f}s   （任务本身只要毫秒级）")
PYEOF

"$CELERY" -A celeryapp control shutdown > /dev/null 2>&1 || true
sleep 2
pkill -f celeryd > /dev/null 2>&1 || true
sleep 2

echo
echo "##################################################"
echo "# 场景 B：快慢分开队列 —— 慢任务走 bulk，快任务走 fast"
echo "#          两个 worker 各管一个队列"
echo "##################################################"

redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

# worker1：只消费 bulk（慢任务）
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 \
    --prefetch-multiplier=1 -Q bulk -n bulk@%h \
    --loglevel=WARNING --logfile=/tmp/l9-bulk.log --detach \
    --pidfile=/tmp/l9-bulk.pid 2>&1 | tail -1

# worker2：只消费 fast（快任务）
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 \
    --prefetch-multiplier=1 -Q fast -n fast@%h \
    --loglevel=WARNING --logfile=/tmp/l9-fast.log --detach \
    --pidfile=/tmp/l9-fast.pid 2>&1 | tail -1
sleep 4

"$PY" - <<'PYEOF'
import time
from celery import group
from celeryapp import app

# 同样先灌 20 个慢任务，但走 bulk 队列
for i in range(20):
    app.send_task('l9.slow_task', args=[i], queue='bulk')

# 快任务走 fast 队列
t0 = time.time()
fast = group(app.signature('l9.fast_task', args=[i], queue='fast') for i in range(5))
res = fast.apply_async()
res.get(timeout=600)
el = time.time() - t0
print(f"RESULT_B 快任务等待耗时 = {el:.2f}s   （队列隔离后）")
PYEOF

"$CELERY" -A celeryapp control shutdown > /dev/null 2>&1 || true
sleep 2
pkill -f celeryd > /dev/null 2>&1 || true

echo
echo "=============================================="
echo "测试结束（对比 RESULT_A 与 RESULT_B）"

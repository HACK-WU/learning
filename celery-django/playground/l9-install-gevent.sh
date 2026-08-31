#!/usr/bin/env bash
# 补装 gevent 并重测 IO 密集场景
set -u

echo "=== 1. 安装 gevent ==="
/tmp/l9venv/bin/pip install -q gevent 2>&1 | tail -3
/tmp/l9venv/bin/python -c 'import gevent; print("gevent", gevent.__version__)'

echo
echo "=== 2. 重测 gevent (200 个 sleep(0.5)) ==="
cd /mnt/d/projects/learning/celery-django/playground/l9demo
CELERY=/tmp/l9venv/bin/celery

redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

"$CELERY" -A celeryapp worker --pool=gevent --concurrency=200 \
    --prefetch-multiplier=1 \
    --loglevel=WARNING --logfile=/tmp/l9-worker-gevent.log --detach \
    --pidfile=/tmp/l9-worker.pid 2>&1 | tail -2
sleep 5

/tmp/l9venv/bin/python - <<'PYEOF'
import time
from celery import group
from celeryapp import app

N = 200
t0 = time.time()
g = group(app.signature('l9.io_task', kwargs={'seconds': 0.5}) for _ in range(N))
res = g.apply_async()
res.get(timeout=600)
el = time.time() - t0
print(f"RESULT {N}个IO任务总耗时 = {el:.2f}s")
PYEOF

"$CELERY" -A celeryapp control shutdown > /dev/null 2>&1 || true
sleep 2
pkill -f celeryd > /dev/null 2>&1 || true

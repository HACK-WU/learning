#!/usr/bin/env bash
# 实测 2：IO 密集任务下 prefork vs threads vs gevent 的并发差异
# 200 个 sleep(0.5) 任务，看谁先跑完
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
PY=/tmp/l9venv/bin/python
CELERY=/tmp/l9venv/bin/celery

run_bench () {
  local POOL=$1
  local CONC=$2
  echo "=============================================="
  echo "POOL=${POOL}  CONCURRENCY=${CONC}  (200 个 sleep(0.5) 任务)"
  echo "=============================================="

  redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
  redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

  "$CELERY" -A celeryapp worker --pool="$POOL" --concurrency="$CONC" \
      --prefetch-multiplier=1 \
      --loglevel=WARNING --logfile=/tmp/l9-worker.log --detach \
      --pidfile=/tmp/l9-worker.pid 2>&1 | tail -2
  sleep 4

  "$PY" - <<'PYEOF'
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
  pkill -f 'celeryd' > /dev/null 2>&1 || true
  sleep 1
}

run_bench prefork 8
run_bench threads 200
run_bench gevent 200

echo "=============================================="
echo "测试结束"

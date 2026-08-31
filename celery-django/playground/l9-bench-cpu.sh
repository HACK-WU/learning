#!/usr/bin/env bash
# 实测 1：CPU 密集任务下 prefork vs threads 的吞吐差异
# 做法：起一个 worker（指定 pool 与并发数）→ 投递 8 个 CPU 任务 → 计时 → 关机
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
PY=/tmp/l9venv/bin/python
CELERY=/tmp/l9venv/bin/celery

run_bench () {
  local POOL=$1
  local CONC=$2
  echo "=============================================="
  echo "POOL=${POOL}  CONCURRENCY=${CONC}"
  echo "=============================================="

  # 清掉上轮残留
  redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
  redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

  # 起 worker
  "$CELERY" -A celeryapp worker --pool="$POOL" --concurrency="$CONC" \
      --loglevel=WARNING --logfile=/tmp/l9-worker.log --detach \
      --pidfile=/tmp/l9-worker.pid 2>&1 | tail -2
  sleep 4

  # 投递 8 个 CPU 任务并计时
  "$PY" - <<'PYEOF'
import time
from celery import group
from celeryapp import app

t0 = time.time()
g = group(app.signature('l9.cpu_task', args=(12_000_000,)) for _ in range(8))
res = g.apply_async()
res.get(timeout=300)          # 等全部完成
el = time.time() - t0
print(f"RESULT 8个CPU任务总耗时 = {el:.2f}s")
PYEOF

  # 关机
  "$CELERY" -A celeryapp control shutdown > /dev/null 2>&1 || true
  sleep 2
  pkill -f 'celeryd' > /dev/null 2>&1 || true
  sleep 1
}

run_bench prefork 8
run_bench threads 8

echo "=============================================="
echo "测试结束"

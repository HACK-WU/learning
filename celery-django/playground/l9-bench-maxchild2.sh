#!/usr/bin/env bash
# 实测 8b：--max-tasks-per-child 防内存泄漏（修正 pidfile 残留问题）
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python

cleanup () {
  "$CELERY" -A celeryapp control shutdown > /dev/null 2>&1 || true
  sleep 1
  pkill -9 -f 'celery.*worker' > /dev/null 2>&1 || true
  rm -f /tmp/l9-worker.pid /tmp/l9-m0.pid /tmp/l9-m2.pid
  sleep 2
}

run_case () {
  local LABEL=$1
  local EXTRA=$2
  local PIDFILE=$3

  echo "###################################################"
  echo "# $LABEL"
  echo "###################################################"
  cleanup
  redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
  redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

  # shellcheck disable=SC2086
  "$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
      --prefetch-multiplier=1 $EXTRA \
      -l WARNING --logfile="/tmp/l9-${LABEL}.log" \
      --pidfile="$PIDFILE" --detach 2>&1 | tail -1
  sleep 5

  echo "--- 跑 6 轮（每轮 2 个任务），记录 PID ---"
  for round in 1 2 3 4 5 6; do
    PIDS=$("$PY" -c "
from celery import group
from celeryapp import app
g = group(app.signature('l9.io_task', kwargs={'seconds': 0.1}) for _ in range(2))
res = g.apply_async().get(timeout=60)
print(sorted({x['pid'] for x in res}))
" 2>&1 | tail -1)
    echo "  第 $round 轮 PID: $PIDS"
  done
  echo
}

run_case "nomaxtasks" "" /tmp/l9-m0.pid
run_case "maxtasks2" "--max-tasks-per-child=2" /tmp/l9-m2.pid

cleanup
echo "==============================================="
echo "测试结束"

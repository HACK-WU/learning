#!/usr/bin/env bash
# 课 10 实测 1：events 机制（稳健版，分步执行）
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python

cleanup () {
  pkill -f 'celeryapp worker' > /dev/null 2>&1 || true
  pkill -f 'celeryapp events' > /dev/null 2>&1 || true
  rm -f /tmp/l10-worker.pid
  sleep 2
  return 0
}

start_worker () {
  local EXTRA="$1"
  local LOGF="$2"
  redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
  redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true
  # shellcheck disable=SC2086
  "$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
      --prefetch-multiplier=1 $EXTRA \
      -l WARNING --logfile="$LOGF" \
      --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
  sleep 5
  return 0
}

send_tasks () {
  "$PY" - <<'PYEOF' || true
from celeryapp import app
for i in range(5):
    app.send_task('l9.io_task', kwargs={'seconds': 0.2})
print('sent 5 tasks')
PYEOF
  return 0
}

echo "########## 实验 A：不开 -E（默认关闭事件） ##########"
cleanup
start_worker "" /tmp/l10-a.log

( timeout 9 "$CELERY" -A celeryapp events --dump > /tmp/l10-events-a.txt 2>&1 || true ) &
EV_PID=$!
sleep 3
send_tasks
wait $EV_PID 2>/dev/null || true

echo "--- 事件统计 ---"
echo "输出总行数: $(wc -l < /tmp/l10-events-a.txt 2>/dev/null || echo 0)"
grep -oE 'task-[a-z-]+|worker-[a-z-]+' /tmp/l10-events-a.txt 2>/dev/null | sort | uniq -c || echo "(无任何任务事件)"
echo "--- 原始输出前 10 行 ---"
head -10 /tmp/l10-events-a.txt 2>/dev/null || echo "(空)"

cleanup

echo
echo "########## 实验 B：开 -E（启用任务事件） ##########"
start_worker "-E" /tmp/l10-b.log

( timeout 11 "$CELERY" -A celeryapp events --dump > /tmp/l10-events-b.txt 2>&1 || true ) &
EV_PID=$!
sleep 3
send_tasks
wait $EV_PID 2>/dev/null || true

echo "--- 事件统计 ---"
echo "输出总行数: $(wc -l < /tmp/l10-events-b.txt 2>/dev/null || echo 0)"
grep -oE 'task-[a-z-]+|worker-[a-z-]+' /tmp/l10-events-b.txt 2>/dev/null | sort | uniq -c || echo "(无事件)"
echo "--- 原始输出前 25 行 ---"
head -25 /tmp/l10-events-b.txt 2>/dev/null || echo "(空)"

cleanup
echo
echo "==============================================="
echo "测试结束"
exit 0

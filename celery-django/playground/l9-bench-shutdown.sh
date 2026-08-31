#!/usr/bin/env bash
# 实测 5：优雅停机 —— warm(TERM) vs cold(QUIT) 的行为差异
# 观察点：① TERM 后任务是否能跑完 ② 未完成任务是否会重新入队（Restoring N unacknowledged message(s)）
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python

cleanup () {
  "$CELERY" -A celeryapp control shutdown > /dev/null 2>&1 || true
  sleep 1
  pkill -f celeryd > /dev/null 2>&1 || true
  sleep 1
}

echo "##################################################"
echo "# 场景 A：WARM shutdown (TERM) —— 默认行为"
echo "# 投一个 12s 的长任务，3s 后发 TERM，看它是否被允许跑完"
echo "##################################################"

redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 \
    --loglevel=INFO --logfile=/tmp/l9-term.log --detach \
    --pidfile=/tmp/l9-worker.pid 2>&1 | tail -1
sleep 4

WPID=$(cat /tmp/l9-worker.pid)
echo "worker pid = $WPID"

# 投递长任务
"$PY" -c "
from celeryapp import app
r = app.send_task('l9.long_task', kwargs={'seconds': 12})
print('task_id =', r.id)
" > /tmp/l9-taskid.txt 2>&1
cat /tmp/l9-taskid.txt

sleep 3
echo ">>> 3s 后发送 TERM（warm shutdown）"
kill -TERM "$WPID"

# 等待 worker 退出，计时
T0=$(date +%s)
for i in $(seq 1 40); do
  if ! kill -0 "$WPID" 2>/dev/null; then break; fi
  sleep 0.5
done
T1=$(date +%s)
echo ">>> worker 在 TERM 后 $((T1-T0))s 退出"

echo "--- 日志关键行 ---"
grep -E 'Warm shutdown|Restoring|unacknowledged|long_task running|Task .* succeeded' /tmp/l9-term.log | head -25

cleanup

echo
echo "##################################################"
echo "# 场景 B：COLD shutdown (QUIT) —— 立刻终止"
echo "##################################################"

redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 \
    --loglevel=INFO --logfile=/tmp/l9-quit.log --detach \
    --pidfile=/tmp/l9-worker.pid 2>&1 | tail -1
sleep 4

WPID=$(cat /tmp/l9-worker.pid)
echo "worker pid = $WPID"

"$PY" -c "
from celeryapp import app
r = app.send_task('l9.long_task', kwargs={'seconds': 12})
print('task_id =', r.id)
"

sleep 3
echo ">>> 3s 后发送 QUIT（cold shutdown）"
kill -QUIT "$WPID"

T0=$(date +%s)
for i in $(seq 1 40); do
  if ! kill -0 "$WPID" 2>/dev/null; then break; fi
  sleep 0.5
done
T1=$(date +%s)
echo ">>> worker 在 QUIT 后 $((T1-T0))s 退出"

echo "--- 日志关键行 ---"
grep -E 'cold shutdown|Restoring|unacknowledged|long_task running|Terminated' /tmp/l9-quit.log | head -25

cleanup
echo
echo "=============================================="
echo "测试结束"

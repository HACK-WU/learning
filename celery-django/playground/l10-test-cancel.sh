#!/usr/bin/env bash
# 决策 2 核心验证：ETA 延迟任务的"可取消性"
# 场景：用户下单后 15 分钟未支付则关单；但用户可能在 1 分钟后就支付了
#      → 已发出的 ETA 任务能不能取消？这是 ETA 方案 vs 轮询方案的关键差异
set -u

APPDIR=/mnt/d/projects/learning/celery-django/playground/l10etatest
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python
LOG=/tmp/l10_eta_exec.log

cleanup () {
  pkill -9 -f 'celeryapp worker' > /dev/null 2>&1 || true
  rm -f /tmp/l10-worker.pid
  sleep 2
  return 0
}

cleanup
redis-cli -p 6380 -n 3 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 4 FLUSHDB > /dev/null 2>&1 || true
rm -f "$LOG"

cd "$APPDIR" || exit 0
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 -l INFO \
    --logfile=/tmp/l10-cancel.log --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

echo "#####################################################"
echo "# 步骤 1：用户下单，发一个 25 秒后执行的关单任务"
echo "#####################################################"
"$PY" - <<'PYEOF' > /tmp/l10_cancel_id.txt 2>&1 || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import eta_task
r = eta_task.apply_async(args=['close_order_1001'], countdown=25)
print(r.id)
PYEOF
TASK_ID=$(cat /tmp/l10_cancel_id.txt | tail -1)
echo "关单任务 id = ${TASK_ID:0:8}"

echo
echo "#####################################################"
echo "# 步骤 2：用户 5 秒后就支付了 → 要取消这个关单任务"
echo "#####################################################"
sleep 5
"$PY" - <<PYEOF || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import app
from celery.result import AsyncResult

tid = "$TASK_ID"
r = AsyncResult(tid, app=app)
print('取消前状态 =', r.state)
app.control.revoke(tid, terminate=False)      # 撤销（不强制终止）
print('已调用 revoke')
PYEOF

echo
echo "#####################################################"
echo "# 步骤 3：等到原定执行时间之后，看任务还会不会跑"
echo "#####################################################"
sleep 30
echo "--- 执行记录（若为空 = 撤销成功）---"
cat "$LOG" 2>/dev/null || echo "(无执行记录 —— 撤销成功，关单任务没有执行)"
echo "执行次数 = $(wc -l < "$LOG" 2>/dev/null || echo 0)"

echo
echo "#####################################################"
echo "# 步骤 4：对照 —— 用户支付后，任务已经开跑了才取消"
echo "#####################################################"
rm -f "$LOG"
"$PY" - <<'PYEOF' > /tmp/l10_cancel_id2.txt 2>&1 || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import long_run_task
r = long_run_task.apply_async(args=['running_task', 20])
print(r.id)
PYEOF
TID2=$(cat /tmp/l10_cancel_id2.txt | tail -1)
echo "运行中任务 id = ${TID2:0:8}"
sleep 4
"$PY" - <<PYEOF || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import app
from celery.result import AsyncResult
tid = "$TID2"
r = AsyncResult(tid, app=app)
print('取消前状态 =', r.state)
app.control.revoke(tid, terminate=False)     # ⚠️ 不 terminate
print('已调用 revoke(terminate=False)')
PYEOF

sleep 20
echo "--- 已在运行的任务被 revoke 后，会继续跑完吗？---"
cat "$LOG" 2>/dev/null || echo "(无记录)"
echo "DONE 次数 = $(grep -c DONE "$LOG" 2>/dev/null || echo 0)  ← =1 说明 revoke 拦不住已开跑的任务"

cleanup
echo
echo "==============================================="
echo "测试结束"
exit 0

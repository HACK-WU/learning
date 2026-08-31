#!/usr/bin/env bash
# 诊断：为什么没有复现"执行时长 > visibility_timeout → 重复执行"？
# 假设：kombu 的新版本有 visibility_timeout 自动续期机制（heartbeat 续约）
# 验证：把 worker 在任务执行中途 SIGKILL，看消息是否被恢复并重新投递
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

echo "#####################################################"
echo "# 场景：任务执行中 SIGKILL worker（模拟宕机）"
echo "#       visibility_timeout=5，任务执行 30 秒"
echo "#####################################################"
cleanup
redis-cli -p 6380 -n 3 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 4 FLUSHDB > /dev/null 2>&1 || true
rm -f "$LOG"

cd "$APPDIR" || exit 0
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 -l INFO \
    --logfile=/tmp/l10-kill.log --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

"$PY" - <<'PYEOF' || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import long_run_task
r = long_run_task.apply_async(args=['kill_mid', 30])
print('已发送 kill_mid（执行 30 秒），id=', r.id[:8])
PYEOF

sleep 8
echo "--- 任务开始执行了吗？---"
cat "$LOG" 2>/dev/null || echo "(无记录)"

echo
echo "--- 现在 SIGKILL 整个 worker（模拟宕机/被 OOM kill）---"
pkill -9 -f 'celeryapp worker' || true
sleep 3
echo "worker 已杀掉"

echo
echo "--- 队列里是否还有这条消息（待恢复）？---"
echo "celery 队列长度 = $(redis-cli -p 6380 -n 3 LLEN celery)"
redis-cli -p 6380 -n 3 LRANGE celery 0 -1 2>/dev/null | head -c 400 || true
echo

echo "--- 重新启动 worker，看消息是否被恢复重投 ---"
cd "$APPDIR" || exit 0
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 -l INFO \
    --logfile=/tmp/l10-kill2.log --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 35

echo "--- 最终执行记录 ---"
cat "$LOG" 2>/dev/null || echo "(无记录)"
echo "START 次数 = $(grep -c START "$LOG" 2>/dev/null || echo 0)"

echo
echo "--- 新 worker 日志中的恢复痕迹 ---"
grep -iE 'Restoring|visibility|recover|unacked|Received task' /tmp/l10-kill2.log | head -12 || true

cleanup
echo
echo "==============================================="
echo "诊断结束"
exit 0

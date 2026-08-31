#!/usr/bin/env bash
# 验证：任务执行时长 > visibility_timeout → 重复执行？（经典场景）
set -u

APPDIR=/mnt/d/projects/learning/celery-django/playground/l10etatest
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python
LOG=/tmp/l10_eta_exec.log

cleanup () {
  pkill -f 'celeryapp worker' > /dev/null 2>&1 || true
  rm -f /tmp/l10-worker.pid
  sleep 2
  return 0
}

echo "#####################################################"
echo "# 场景：执行 20 秒 > visibility_timeout=5"
echo "#       acks_late=True（生产推荐配置）"
echo "#####################################################"
cleanup
redis-cli -p 6380 -n 3 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 4 FLUSHDB > /dev/null 2>&1 || true
rm -f "$LOG"

cd "$APPDIR" || exit 0
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 -l WARNING \
    --logfile=/tmp/l10-longrun.log --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

"$PY" - <<'PYEOF' || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import long_run_task
r = long_run_task.apply_async(args=['slow_20s', 20])
print('已发送 slow_20s（执行 20 秒），id=', r.id[:8])
PYEOF

echo "等待 40 秒，观察是否被重复投递..."
sleep 40

echo "--- 执行记录 ---"
cat "$LOG" 2>/dev/null || echo "(无执行记录)"
echo "START 次数 = $(grep -c START "$LOG" 2>/dev/null || echo 0)   ← >1 即重复执行"

echo
echo "--- worker 日志中的重复/恢复痕迹 ---"
grep -iE 'Restoring|visibility|lost|acks_late|Received task' /tmp/l10-longrun.log | head -12 || true

cleanup
echo
echo "==============================================="
echo "测试结束"
exit 0

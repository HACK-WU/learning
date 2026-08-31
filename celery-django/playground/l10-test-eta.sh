#!/usr/bin/env bash
# 验证：ETA/countdown 任务 + Redis broker + acks_late + 短 visibility_timeout → 重复执行？
# 这是「决策 2：超时未支付订单怎么取消」所依赖的关键行为，必须实测不能凭记忆
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
echo "# 场景 A：countdown=20 > visibility_timeout=1（极短）"
echo "#         acks_late=True（生产推荐配置）"
echo "#####################################################"
cleanup
redis-cli -p 6380 -n 3 FLUSHDB > /dev/null 2>&1 || true
redis-cli -p 6380 -n 4 FLUSHDB > /dev/null 2>&1 || true
rm -f "$LOG"

cd "$APPDIR" || exit 0
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 -l WARNING \
    --logfile=/tmp/l10-eta.log --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

"$PY" - <<'PYEOF' || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import eta_task
r = eta_task.apply_async(args=['long_eta'], countdown=20)
print('已发送 long_eta，countdown=20，id=', r.id[:8])
PYEOF

echo "等待 60 秒，观察执行次数（若 >1 说明被重复投递）..."
sleep 60

echo "--- 执行记录 ---"
cat "$LOG" 2>/dev/null || echo "(无执行记录)"
echo "执行次数 = $(wc -l < "$LOG" 2>/dev/null || echo 0)"

echo
echo "#####################################################"
echo "# 场景 B（对照）：countdown=3 < visibility_timeout=8"
echo "#####################################################"
cleanup
redis-cli -p 6380 -n 3 FLUSHDB > /dev/null 2>&1 || true
rm -f "$LOG"

cd "$APPDIR" || exit 0
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 -l WARNING \
    --logfile=/tmp/l10-eta2.log --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

"$PY" - <<'PYEOF' || true
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l10etatest')
from celeryapp import eta_task
r = eta_task.apply_async(args=['short_eta'], countdown=3)
print('已发送 short_eta，countdown=3，id=', r.id[:8])
PYEOF

sleep 20
echo "--- 执行记录 ---"
cat "$LOG" 2>/dev/null || echo "(无执行记录)"
echo "执行次数 = $(wc -l < "$LOG" 2>/dev/null || echo 0)"

cleanup
echo
echo "==============================================="
echo "测试结束"
exit 0

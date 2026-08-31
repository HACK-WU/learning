#!/usr/bin/env bash
# 课 10 实测 2：worker 假死（僵尸任务）—— 任务卡住不返回，槽位被占满
# 观察：inspect active 显示任务一直在跑，但永远不结束；新任务无槽位可用
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python

cleanup () {
  pkill -f 'celeryapp worker' > /dev/null 2>&1 || true
  rm -f /tmp/l10-worker.pid
  sleep 2
  return 0
}

echo "###################################################"
echo "# 场景：worker -c 2，投 2 个"永久卡住"的任务占满槽位"
echo "#       再投第 3 个正常任务，看它是否一直排不上"
echo "###################################################"
cleanup
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

# 造一个"卡死任务"：不带 time_limit 的死循环
cat > /tmp/l10_hang.py <<'PYEOF'
from celeryapp import app

@app.task(name='l10.hang_task')
def hang_task():
    """模拟卡死：死循环，永不返回（无 time_limit 保护）。"""
    while True:
        pass
PYEOF
cp /tmp/l10_hang.py /mnt/d/projects/learning/celery-django/playground/l9demo/l10_hang.py

# 让 worker 导入该模块
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 --include=l10_hang \
    -l WARNING --logfile=/tmp/l10-hang.log \
    --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

echo "--- 投 2 个卡死任务，占满 2 个槽位 ---"
"$PY" - <<'PYEOF' || true
from celeryapp import app
for i in range(2):
    print('sent hang', app.send_task('l10.hang_task').id[:8])
PYEOF

sleep 3
echo "--- 投 1 个正常快任务，看它是否被堵死 ---"
"$PY" - <<'PYEOF' || true
from celeryapp import app
r = app.send_task('l9.io_task', kwargs={'seconds': 0.1})
print('fast task id =', r.id[:8])
PYEOF

sleep 5
echo
echo "--- inspect active（应该看到 2 个 hang 任务在跑）---"
"$CELERY" -A celeryapp inspect active 2>/dev/null | head -20 || true

echo
echo "--- inspect stats（看 active 槽位占用）---"
"$CELERY" -A celeryapp inspect stats 2>/dev/null | grep -E '"active"|"total"|pool' | head -10 || true

echo
echo "--- 队列残留（快任务是不是还躺着？）---"
echo "celery 队列长度 = $(redis-cli -p 6380 -n 0 LLEN celery)"

echo
echo "--- 快任务结果（等 5 秒，应该超时拿不到）---"
"$PY" - <<'PYEOF' || true
import time
from celeryapp import app
from celery.result import AsyncResult
# 取最后一个 io_task 的结果
r = app.send_task('l9.io_task', kwargs={'seconds': 0.1})
t0 = time.time()
try:
    res = r.get(timeout=6)
    print(f"拿到结果: {res}  耗时 {time.time()-t0:.1f}s")
except Exception as e:
    print(f"6秒内没拿到结果（槽位被卡死任务占满）: {type(e).__name__}")
PYEOF

cleanup
rm -f /mnt/d/projects/learning/celery-django/playground/l9demo/l10_hang.py
echo
echo "==============================================="
echo "测试结束"
exit 0

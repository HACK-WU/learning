#!/usr/bin/env bash
# 实测（修正版）：soft_time_limit 自动解除卡死
# 修正点：SoftTimeLimitExceeded 正确导入路径为 celery.exceptions
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

cat > /mnt/d/projects/learning/celery-django/playground/l9demo/l10_soft.py <<'PYEOF'
import os, time
from celery.exceptions import SoftTimeLimitExceeded    # ← 正确导入路径
from celeryapp import app

@app.task(name='l10.soft_task', bind=True, soft_time_limit=3, time_limit=9)
def soft_task(self):
    """软超时 3s：可被捕获做清理；硬超时 9s 兜底硬杀。"""
    print(f'[SOFT] 开始 pid={os.getpid()}', flush=True)
    try:
        for i in range(60):
            time.sleep(0.5)
    except SoftTimeLimitExceeded:
        print('[SOFT] 捕获软超时，执行清理后退出', flush=True)
        return {'cleaned': True}
    return {'done': True}

@app.task(name='l10.busy_task', bind=True, soft_time_limit=3, time_limit=9)
def busy_task(self):
    """纯 CPU 忙循环：模拟"不可中断"的计算型卡死。"""
    print(f'[BUSY] 开始 pid={os.getpid()}', flush=True)
    try:
        acc = 0
        while True:
            acc += 1
    except SoftTimeLimitExceeded:
        print('[BUSY] 捕获软超时', flush=True)
        return {'cleaned': True}
PYEOF

echo "=== 1. 确认导入正确 ==="
"$PY" -c "
import sys
sys.path.insert(0, '/mnt/d/projects/learning/celery-django/playground/l9demo')
import l10_soft
from celeryapp import app
print('已注册:', [t for t in app.tasks if t.startswith('l10.')])
" 2>&1

echo
echo "###################################################"
echo "# 实验 A：可中断阻塞（time.sleep）+ soft_time_limit=3"
echo "###################################################"
cleanup
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 --include=l10_soft \
    -l INFO --logfile=/tmp/l10-soft.log \
    --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

"$PY" - <<'PYEOF' || true
import time
from celeryapp import app
t0 = time.time()
r = app.send_task('l10.soft_task')
try:
    res = r.get(timeout=25)
    print(f"RESULT {res}  耗时 {time.time()-t0:.1f}s  ← 卡死被自动解除")
except Exception as e:
    print(f"失败 {type(e).__name__}: {e}")
PYEOF

echo
echo "--- 日志证据 ---"
grep -E '\[SOFT\]|SoftTimeLimit|succeeded' /tmp/l10-soft.log | head -10 || true

echo
echo "--- 槽位是否释放 ---"
"$CELERY" -A celeryapp inspect stats 2>/dev/null | grep -E '"active"|"total"' | head -6 || true

echo
echo "###################################################"
echo "# 实验 B：CPU 忙循环（不可中断）+ time_limit=9 硬杀"
echo "###################################################"
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

"$PY" - <<'PYEOF' || true
import time
from celeryapp import app
t0 = time.time()
r = app.send_task('l10.busy_task')
try:
    res = r.get(timeout=25)
    print(f"RESULT {res}  耗时 {time.time()-t0:.1f}s")
except Exception as e:
    print(f"任务被终止: {type(e).__name__}: {str(e)[:120]}  耗时 {time.time()-t0:.1f}s")
PYEOF

sleep 2
echo
echo "--- 日志证据（硬超时/Worker Lost）---"
grep -iE '\[BUSY\]|TimeLimitExceeded|Worker Lost|Hard time limit|SoftTimeLimit' /tmp/l10-soft.log | head -12 || true

echo
echo "--- 槽位是否恢复 ---"
"$CELERY" -A celeryapp inspect stats 2>/dev/null | grep -E '"active"|"total"' | head -6 || true

cleanup
rm -f /mnt/d/projects/learning/celery-django/playground/l9demo/l10_soft.py
echo
echo "==============================================="
echo "测试结束"
exit 0

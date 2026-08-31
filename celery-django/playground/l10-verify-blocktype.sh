#!/usr/bin/env bash
# 验证：到底什么情况下 soft_time_limit 捕获不到？
# 对比三种阻塞：① time.sleep（可中断）② 纯 Python 忙循环 ③ 真正不可中断的 C 调用
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

cat > /mnt/d/projects/learning/celery-django/playground/l9demo/l10_block.py <<'PYEOF'
import os, time, signal
from celery.exceptions import SoftTimeLimitExceeded
from celeryapp import app

@app.task(name='l10.blk_sleep', bind=True, soft_time_limit=3, time_limit=10)
def blk_sleep(self):
    """① time.sleep：Python 层阻塞，可被信号中断。"""
    print(f'[SLEEP] start pid={os.getpid()}', flush=True)
    try:
        while True:
            time.sleep(0.2)
    except SoftTimeLimitExceeded:
        print('[SLEEP] caught soft limit', flush=True)
        return {'caught': 'sleep'}

@app.task(name='l10.blk_pybusy', bind=True, soft_time_limit=3, time_limit=10)
def blk_pybusy(self):
    """② 纯 Python 忙循环：字节码边界会检查信号。"""
    print(f'[PYBUSY] start pid={os.getpid()}', flush=True)
    try:
        acc = 0
        while True:
            acc += 1
    except SoftTimeLimitExceeded:
        print('[PYBUSY] caught soft limit', flush=True)
        return {'caught': 'pybusy'}

@app.task(name='l10.blk_blocksignal', bind=True, soft_time_limit=3, time_limit=10)
def blk_blocksignal(self):
    """③ 屏蔽 SIGTERM：模拟"信号根本递达不了"的极端情况（C 扩展卡死类似）。"""
    print(f'[BLOCKED] start pid={os.getpid()}', flush=True)
    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM})
    try:
        while True:
            time.sleep(0.2)
    except SoftTimeLimitExceeded:
        print('[BLOCKED] caught soft limit', flush=True)
        return {'caught': 'blocked'}
PYEOF

run_case () {
  local TASK=$1
  local LABEL=$2
  echo "---------------------------------------------"
  echo "▶ $LABEL"
  echo "---------------------------------------------"
  redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
  redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

  "$PY" - <<PYEOF || true
import time
from celeryapp import app
t0 = time.time()
r = app.send_task('$TASK')
try:
    res = r.get(timeout=22)
    print(f"   RESULT {res}  耗时 {time.time()-t0:.1f}s")
except Exception as e:
    print(f"   任务被硬终止/失败: {type(e).__name__}  耗时 {time.time()-t0:.1f}s")
PYEOF
  return 0
}

cleanup
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 --include=l10_block \
    -l INFO --logfile=/tmp/l10-block.log \
    --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

run_case l10.blk_sleep      "① time.sleep（可中断）"
run_case l10.blk_pybusy     "② 纯 Python 忙循环"
run_case l10.blk_blocksignal "③ 屏蔽 SIGTERM（信号递达不了）"

sleep 2
echo
echo "==============================================="
echo "--- 汇总日志证据 ---"
grep -E '\[SLEEP\]|\[PYBUSY\]|\[BLOCKED\]|SoftTimeLimit|TimeLimitExceeded|Worker Lost|Hard time limit' /tmp/l10-block.log | head -20 || true

echo
echo "--- 槽位最终状态 ---"
"$CELERY" -A celeryapp inspect stats 2>/dev/null | grep -E '"active"|"total"' | head -6 || true

cleanup
rm -f /mnt/d/projects/learning/celery-django/playground/l9demo/l10_block.py
echo
echo "==============================================="
echo "验证结束"
exit 0

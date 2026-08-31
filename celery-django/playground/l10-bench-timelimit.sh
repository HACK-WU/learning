#!/usr/bin/env bash
# 课 10 实测 3：用 time_limit / soft_time_limit 自动解除假死
# 对照：无 time_limit（永久卡死） vs 有 soft_time_limit（软超时可捕获） vs time_limit（硬杀）
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

# 造任务模块：三种超时行为
cat > /mnt/d/projects/learning/celery-django/playground/l9demo/l10_timeout.py <<'PYEOF'
import time
from celery import SoftTimeLimitExceeded
from celeryapp import app

@app.task(name='l10.hang_no_limit')
def hang_no_limit():
    """无保护：死循环。"""
    while True:
        pass

@app.task(name='l10.hang_soft', soft_time_limit=3, time_limit=8)
def hang_soft():
    """软超时 3s：可被捕获，用于清理。硬超时 8s 兜底。"""
    try:
        while True:
            time.sleep(0.1)
    except SoftTimeLimitExceeded:
        # 软超时到了，这里做清理（关连接、记日志、释放资源）
        print('[SOFT] 捕获软超时，执行清理后退出', flush=True)
        return {'cleaned': True}
PYEOF

echo "###################################################"
echo "# 实验：soft_time_limit=3 / time_limit=8 能否自动解除卡死"
echo "###################################################"
cleanup
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 --include=l10_timeout \
    -l INFO --logfile=/tmp/l10-timeout.log \
    --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

echo "--- 投递一个"会卡死但带软超时"的任务 ---"
"$PY" - <<'PYEOF' || true
import time
from celeryapp import app

t0 = time.time()
r = app.send_task('l10.hang_soft')
try:
    res = r.get(timeout=20)
    print(f"RESULT 拿到结果 {res}，耗时 {time.time()-t0:.1f}s  ← 卡死被自动解除")
except Exception as e:
    print(f"失败: {type(e).__name__}: {e}")
PYEOF

echo
echo "--- worker 日志关键行（软超时证据）---"
grep -iE 'SoftTimeLimitExceeded|SOFT|TimeLimitExceeded|raised|succeeded' /tmp/l10-timeout.log | head -12 || true

echo
echo "--- 槽位是否已释放（active 应该回到 0）---"
"$CELERY" -A celeryapp inspect stats 2>/dev/null | grep -E '"active"|"total"' | head -6 || true

cleanup
rm -f /mnt/d/projects/learning/celery-django/playground/l9demo/l10_timeout.py
echo
echo "==============================================="
echo "测试结束"
exit 0

#!/usr/bin/env bash
# 实测 7：Soft Shutdown（用 app.conf 注入，确保配置生效）
# 关键点：
#   worker_soft_shutdown_timeout > 0  → 启用 soft shutdown
#   REMAP_SIGTERM=SIGQUIT            → TERM 走 cold 流程（容器环境标准做法）
# 观察："Initiating Soft Shutdown" + "Restoring N unacknowledged message(s)"
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo
CELERY=/tmp/l9venv/bin/celery
PY=/tmp/l9venv/bin/python

cleanup () { pkill -f celeryd > /dev/null 2>&1 || true; sleep 1; }

echo "###################################################"
echo "# 对照：soft_shutdown_timeout=0（默认，关闭）"
echo "###################################################"
cleanup
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

cat > /tmp/l9_conf_off.py <<'PYEOF'
from celeryapp import app
app.conf.worker_soft_shutdown_timeout = 0.0      # 关闭
app.conf.task_acks_late = True
PYEOF

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 -l INFO --logfile=/tmp/l9-off.log \
    --detach --pidfile=/tmp/l9-worker.pid 2>&1 | tail -1
sleep 4
WPID=$(cat /tmp/l9-worker.pid)

"$PY" -c "
from celeryapp import app
for i in range(3):
    print('sent', app.send_task('l9.long_task', kwargs={'seconds': 30}).id[:8])
"
sleep 3
echo ">>> 发送 QUIT（cold shutdown）"
kill -QUIT "$WPID"
T0=$(date +%s)
for i in $(seq 1 40); do kill -0 "$WPID" 2>/dev/null || break; sleep 0.5; done
echo ">>> 退出耗时 $(( $(date +%s) - T0 ))s"
echo "--- 日志 ---"
grep -iE 'Soft Shutdown|Restoring|unacknowledged' /tmp/l9-off.log | head -5
echo "队列残留 = $(redis-cli -p 6380 -n 0 LLEN celery)"
cleanup

echo
echo "###################################################"
echo "# 实验：soft_shutdown_timeout=15（开启）"
echo "###################################################"
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null

cat > /tmp/l9_conf_on.py <<'PYEOF'
from celeryapp import app
app.conf.worker_soft_shutdown_timeout = 15.0     # 开启：给 15s 宽限
app.conf.worker_enable_soft_shutdown_on_idle = True
app.conf.task_acks_late = True
PYEOF

# 用 imports 钩子注入配置：起 worker 时通过 --include 加载
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=2 \
    --prefetch-multiplier=1 -l INFO --logfile=/tmp/l9-on.log \
    --include=l9conf_on \
    --detach --pidfile=/tmp/l9-worker.pid 2>&1 | tail -1
sleep 4
WPID=$(cat /tmp/l9-worker.pid)

"$PY" -c "
from celeryapp import app
for i in range(3):
    print('sent', app.send_task('l9.long_task', kwargs={'seconds': 30}).id[:8])
"
sleep 3
echo ">>> 发送 QUIT（cold shutdown → 触发 soft 阶段）"
kill -QUIT "$WPID"
T0=$(date +%s)
for i in $(seq 1 60); do kill -0 "$WPID" 2>/dev/null || break; sleep 0.5; done
echo ">>> 退出耗时 $(( $(date +%s) - T0 ))s"
echo "--- 日志 ---"
grep -iE 'Soft Shutdown|Restoring|unacknowledged' /tmp/l9-on.log | head -5
echo "队列残留 = $(redis-cli -p 6380 -n 0 LLEN celery)"
cleanup

echo
echo "==============================================="
echo "测试结束"

#!/usr/bin/env bash
# 课 10 实测 4：result backend 撑爆 —— 每个结果都是一条永久 Redis key
# 对照：task_ignore_result=False（默认） vs True
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

N=300

echo "###################################################"
echo "# 实验：投 $N 个任务，看 backend 里堆积多少 key"
echo "###################################################"
cleanup
redis-cli -p 6380 -n 0 FLUSHDB > /dev/null || true
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

echo "起始：db1（backend）key 数 = $(redis-cli -p 6380 -n 1 DBSIZE)"

"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 \
    --prefetch-multiplier=1 -l WARNING --logfile=/tmp/l10-be.log \
    --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

"$PY" - <<PYEOF || true
from celeryapp import app
for i in range($N):
    app.send_task('l9.io_task', kwargs={'seconds': 0.05})
print('sent $N tasks')
PYEOF

sleep 6
echo
echo "执行后：db1（backend）key 数 = $(redis-cli -p 6380 -n 1 DBSIZE)"
echo "db0（broker）key 数     = $(redis-cli -p 6380 -n 0 DBSIZE)"

echo
echo "--- backend 里的 key 样例（前 5 个）---"
redis-cli -p 6380 -n 1 --scan --pattern 'celery-task-meta-*' 2>/dev/null | head -5 || redis-cli -p 6380 -n 1 KEYS 'celery-task-meta-*' | head -5

echo
echo "--- 单个结果 key 的 TTL（-1 = 永不过期）---"
K=$(redis-cli -p 6380 -n 1 KEYS 'celery-task-meta-*' | head -1)
if [ -n "$K" ]; then
  echo "key=$K  TTL=$(redis-cli -p 6380 -n 1 TTL "$K")"
  echo "值大小 = $(redis-cli -p 6380 -n 1 MEMORY USAGE "$K" 2>/dev/null || echo 'n/a') bytes"
else
  echo "(没有找到结果 key，可能 backend 配置不同)"
fi

echo
echo "--- 设置 result_expires=60 后对比 ---"
redis-cli -p 6380 -n 1 FLUSHDB > /dev/null || true

cat > /mnt/d/projects/learning/celery-django/playground/l9demo/l10_ttl.py <<'PYEOF'
from celeryapp import app
app.conf.result_expires = 60      # 结果只保留 60 秒
PYEOF

cleanup
"$CELERY" -A celeryapp worker --pool=prefork --concurrency=4 \
    --prefetch-multiplier=1 --include=l10_ttl \
    -l WARNING --logfile=/tmp/l10-be2.log \
    --pidfile=/tmp/l10-worker.pid --detach 2>&1 | tail -1 || true
sleep 5

"$PY" - <<PYEOF || true
from celeryapp import app
for i in range($N):
    app.send_task('l9.io_task', kwargs={'seconds': 0.05})
print('sent $N tasks (with result_expires=60)')
PYEOF

sleep 6
echo "执行后：db1 key 数 = $(redis-cli -p 6380 -n 1 DBSIZE)"
K2=$(redis-cli -p 6380 -n 1 KEYS 'celery-task-meta-*' | head -1)
if [ -n "$K2" ]; then
  echo "TTL = $(redis-cli -p 6380 -n 1 TTL "$K2") 秒（有过期时间就不会永久堆积）"
else
  echo "(无 key)"
fi

cleanup
rm -f /mnt/d/projects/learning/celery-django/playground/l9demo/l10_ttl.py
echo
echo "==============================================="
echo "测试结束"
exit 0

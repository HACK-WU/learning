#!/usr/bin/env bash
# 只测 beat 重叠（实验 ① 已出结果，此处不重复）
# 上次 beat 没跑起来，先排查为什么
set -u

VENV=/mnt/d/projects/learning/celery-django/.venv
PY=$VENV/bin/python
CELERY=$VENV/bin/celery
WORK=/mnt/d/projects/learning/celery-django/playground/l11-work

cleanup () {
  pkill -9 -f 'celery -A pw' > /dev/null 2>&1 || true
  sleep 2
  return 0
}

cd "$WORK" || exit 1
cleanup
rm -f overlap.txt celerybeat-schedule* beat.log w3.log
redis-cli -p 6380 -n 9 FLUSHDB > /dev/null 2>&1 || true

echo "=== 0. 检查 beat 配置模块能否被找到 ==="
"$PY" -c "
import beatconf
print('beatconf 可导入, schedule =', beatconf.beat_schedule)
" 2>&1 | tail -5

echo
echo "=== 1. 用 -A pw 启动 worker 并注册任务 ==="
"$CELERY" -A pw worker -c 2 -l INFO --logfile=w3.log --pidfile=w3.pid --detach > /dev/null 2>&1 || true
sleep 5
"$CELERY" -A pw inspect registered 2>&1 | grep -E 'pw\.' | head -5 || echo "(没注册上)"

echo
echo "=== 2. 把 schedule 直接写进 app（不依赖外部模块）==="
cat > pw2.py <<'PYEOF'
from pw import app, overlap_task
app.conf.beat_schedule = {
    'every-3-seconds': {
        'task': 'pw.overlap_task',
        'schedule': 3.0,
        'args': (8,),
    },
}
PYEOF
"$PY" -c "
from pw2 import app
print('beat_schedule =', app.conf.beat_schedule)
" 2>&1 | tail -3

echo
echo "=== 3. 用 pw2 启动 beat ==="
"$CELERY" -A pw2 beat -l DEBUG --schedule=celerybeat-schedule \
    --logfile=beat.log --pidfile=beat.pid --detach 2>&1 | tail -3 || true
sleep 3
echo "beat 进程: $(pgrep -f 'celery -A pw2 beat' | wc -l)"

echo "观察 28 秒..."
sleep 28

echo
echo "=== 4. beat 日志（关键）==="
tail -25 beat.log 2>/dev/null || echo "(无 beat.log)"

echo
echo "=== 5. overlap.txt ==="
if [ -f overlap.txt ]; then
  sort -n overlap.txt
  echo "START = $(grep -c START overlap.txt), END = $(grep -c END overlap.txt)"
else
  echo "(无记录 —— beat 没调度出任务)"
fi

pkill -9 -f 'celery -A pw2 beat' > /dev/null 2>&1 || true
cleanup
echo
echo "==============================================="
echo "beat 实验结束"
exit 0

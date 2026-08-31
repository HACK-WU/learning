#!/usr/bin/env bash
# 精确测量 restore_visible 的实际重投间隔（多组对照）
# 上次实测：START 间隔 88.6 秒。用多组任务耗时测出临界点。
set -u

VENV=/mnt/d/projects/learning/celery-django/.venv
PY=$VENV/bin/python
CELERY=$VENV/bin/celery
WORK=/mnt/d/projects/learning/celery-django/playground/l11-work3
DB=11

cleanup () {
  pkill -9 -f 'celery -A mt' > /dev/null 2>&1 || true
  sleep 2
  return 0
}

rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1

cat > mt.py <<'PYEOF'
from celery import Celery
import time

app = Celery('mt',
    broker='redis://localhost:6380/11',
    backend='redis://localhost:6380/11',
)
app.conf.update(
    task_serializer='json', result_serializer='json', accept_content=['json'],
    task_track_started=True, task_acks_late=True, task_reject_on_worker_lost=True,
    broker_transport_options={'visibility_timeout': 5},
    # 硬超时设长一点，避免任务被 time_limit 杀掉干扰观测
)

@app.task(bind=True, name='mt.slow')
def slow(self, seconds):
    t0 = time.time()
    with open('runs.txt', 'a') as f:
        f.write(f'{t0:.1f} START id={self.request.id[:8]} retries={self.request.retries} dur={seconds}\n')
    time.sleep(seconds)
    with open('runs.txt', 'a') as f:
        f.write(f'{time.time():.1f} END   id={self.request.id[:8]} dur={seconds}\n')
    return seconds
PYEOF

redis-cli -p 6380 -n $DB FLUSHDB > /dev/null 2>&1 || true
cleanup
rm -f runs.txt

"$CELERY" -A mt worker -c 4 -l INFO --logfile=w.log --pidfile=w.pid --detach > /dev/null 2>&1 || true
sleep 5

echo "#####################################################"
echo "# 提交 4 组不同耗时的任务，看哪些会被重投"
echo "#   visibility_timeout = 5 秒（所有组都一样）"
echo "#   预期：耗时 < ~100 秒的不重投；> ~100 秒的会被重投"
echo "#####################################################"

"$PY" -c "
from mt import slow
for dur in [30, 70, 110, 150]:
    r = slow.delay(dur)
    print(f'  提交 dur={dur}s -> {r.id[:8]}')
"

echo
echo "观察 175 秒..."
sleep 175

echo
echo "--- 结果：按 task_id 分组看执行次数 ---"
"$PY" - <<'PYEOF'
import re
from collections import defaultdict
try:
    lines = [l for l in open('runs.txt') if l.strip()]
except FileNotFoundError:
    print('(无记录)'); raise SystemExit

dur_of = {}
starts = defaultdict(list)
for l in lines:
    m = re.search(r'START id=(\w+) retries=(\d+) dur=(\d+)', l)
    if m:
        tid, retries, dur = m.group(1), m.group(2), m.group(3)
        dur_of[tid] = dur
        # 时间戳取行首
        ts = float(l.split()[0])
        starts[tid].append(ts)

for tid, ts_list in starts.items():
    n = len(ts_list)
    gaps = [f'{ts_list[i+1]-ts_list[i]:.1f}s' for i in range(len(ts_list)-1)]
    flag = '🔴 被重投' if n > 1 else '⚪ 只跑一次'
    print(f'  dur={dur_of[tid]:>3}s  id={tid}  执行 {n} 次  {flag}  间隔={gaps}')
PYEOF

cleanup
echo
echo "==============================================="
echo "测量结束"
exit 0

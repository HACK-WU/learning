#!/usr/bin/env bash
# 验证推断：restore_visible 的实际检查间隔 = 10秒 × interval(10) ≈ 100 秒
# 判据：把任务耗时拉到 >> 100 秒 且 >> visibility_timeout，看是否重投
#   若重投 → 推断成立（不是"不会重投"，而是"检查周期太长没来得及"）
#   若仍不重投 → 推断不成立，另有机制
#
# 为了不等太久，用 interval 更小的对照组 + 更长任务两种口径
set -u

VENV=/mnt/d/projects/learning/celery-django/.venv
PY=$VENV/bin/python
CELERY=$VENV/bin/celery
WORK=/mnt/d/projects/learning/celery-django/playground/l11-work2
DB=10

cleanup () {
  pkill -9 -f 'celery -A vt' > /dev/null 2>&1 || true
  sleep 2
  return 0
}

rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1

cat > vt.py <<'PYEOF'
from celery import Celery
import time, os

app = Celery('vt',
    broker='redis://localhost:6380/10',
    backend='redis://localhost:6380/10',
)
app.conf.update(
    task_serializer='json', result_serializer='json', accept_content=['json'],
    task_track_started=True,
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    broker_transport_options={'visibility_timeout': 5},
)

@app.task(bind=True, name='vt.slow')
def slow(self, seconds):
    with open('runs.txt', 'a') as f:
        f.write(f'{time.time():.1f} START id={self.request.id} retries={self.request.retries}\n')
    time.sleep(seconds)
    with open('runs.txt', 'a') as f:
        f.write(f'{time.time():.1f} END   id={self.request.id}\n')
    return seconds
PYEOF

redis-cli -p 6380 -n $DB FLUSHDB > /dev/null 2>&1 || true

echo "#####################################################"
echo "# 验证：任务耗时 150 秒 >> visibility_timeout 5 秒"
echo "#   推断：restore_visible 实际约每 100 秒才检查一次"
echo "#        若推断对，150 秒内应有一次检查 → 应观测到重投"
echo "#####################################################"
cleanup
rm -f runs.txt
"$CELERY" -A vt worker -c 2 -l INFO --logfile=w.log --pidfile=w.pid --detach > /dev/null 2>&1 || true
sleep 5

"$PY" -c "
from vt import slow
r = slow.delay(150)
print('已提交，任务 150 秒，vt=5 秒。后台执行，脚本不阻塞等待。')
print('task_id =', r.id)
"

echo "观察 165 秒（期间不 ack，等待 restore_visible 触发）..."
sleep 165

echo
echo "--- runs.txt ---"
if [ -f runs.txt ]; then
  cat runs.txt
  echo "START 次数 = $(grep -c START runs.txt)"
else
  echo "(无执行)"
fi

cleanup
echo
echo "==============================================="
echo "验证结束"
exit 0

#!/usr/bin/env bash
# Phase 5 补验：两个"常听说但没实测"的关键断言
#  ① 长任务超过 visibility_timeout 是否真的被重投？（官方明确说会，本机上次没复现）
#  ② beat 周期任务：间隔短于任务耗时时，是否会重叠执行？
set -u

VENV=/mnt/d/projects/learning/celery-django/.venv
PY=$VENV/bin/python
CELERY=$VENV/bin/celery
BASE=/mnt/d/projects/learning/celery-django/playground
WORK=$BASE/l11-work
DB=9

cleanup () {
  pkill -9 -f 'celery -A pw' > /dev/null 2>&1 || true
  sleep 2
  return 0
}

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK" || exit 1

cat > pw.py <<'PYEOF'
from celery import Celery
import os, time

app = Celery('pw',
    broker='redis://localhost:6380/9',
    backend='redis://localhost:6380/9',
)
app.conf.update(
    task_serializer='json',
    result_serializer='json',
    accept_content=['json'],
    task_track_started=True,
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    # ⭐ visibility_timeout = 5 秒：远小于任务耗时
    broker_transport_options={'visibility_timeout': 5},
    worker_send_task_events=True,
)

RUNS = []

@app.task(bind=True, name='pw.long_task')
def long_task(self, seconds):
    """耗时 seconds 秒的任务，记录每次开始执行"""
    RUNS.append(time.time())
    with open('runs.txt', 'a') as f:
        f.write(f'{self.request.id} start={time.time():.1f} retries={self.request.retries}\n')
    time.sleep(seconds)
    return {'done': seconds}

@app.task(bind=True, name='pw.overlap_task')
def overlap_task(self, seconds):
    """用于测 beat 重叠：每次执行都记录"""
    t = time.time()
    with open('overlap.txt', 'a') as f:
        f.write(f'{t:.2f} START id={self.request.id}\n')
    time.sleep(seconds)
    with open('overlap.txt', 'a') as f:
        f.write(f'{t:.2f} END   id={self.request.id}\n')
    return 'ok'
PYEOF

redis-cli -p 6380 -n $DB FLUSHDB > /dev/null 2>&1 || true

echo "#####################################################"
echo "# 实验 ①：长任务 vs visibility_timeout"
echo "#   配置：visibility_timeout = 5 秒，任务耗时 20 秒"
echo "#   官方说法：超时未 ack → 重投给另一个 worker → 重复执行"
echo "#   本机上次（countdown 场景）未复现，这次换纯长任务场景"
echo "#####################################################"
cleanup
rm -f runs.txt

# 起两个 worker，让"重投给另一个 worker"有条件发生
"$CELERY" -A pw worker -c 2 -l INFO --logfile=w1.log --pidfile=w1.pid --detach > /dev/null 2>&1 || true
"$CELERY" -A pw worker -c 2 -l INFO --logfile=w2.log --pidfile=w2.pid --detach -n w2@%h > /dev/null 2>&1 || true
sleep 6
echo "worker 数: $("$CELERY" -A pw inspect ping 2>/dev/null | grep -c OK)"

"$PY" - <<'PYEOF'
import time
from pw import long_task
r = long_task.delay(20)   # 耗时 20 秒 >> visibility_timeout 5 秒
print(f'已提交长任务 {r.id}，耗时 20 秒，visibility_timeout=5 秒')
print('等待 45 秒观察是否被重投...')
try:
    print('结果:', r.get(timeout=45))
except Exception as e:
    print(f'get 失败: {type(e).__name__}')
PYEOF

echo
echo "--- runs.txt（每次开始执行都记一行）---"
if [ -f runs.txt ]; then
  echo "执行次数 = $(wc -l < runs.txt)"
  cat runs.txt
else
  echo "(没有 runs.txt，任务一次都没执行)"
fi

echo
echo "#####################################################"
echo "# 实验 ②：beat 定时任务重叠执行"
echo "#   配置：每 3 秒调度一次，任务耗时 8 秒"
echo "#   问题：上一次还没跑完，下一次会不会又开始？"
echo "#####################################################"

cat > beatconf.py <<'PYEOF'
from celery.schedules import timedelta
beat_schedule = {
    'every-3-seconds': {
        'task': 'pw.overlap_task',
        'schedule': 3.0,      # 每 3 秒
        'args': (8,),         # 但任务要跑 8 秒
    },
}
PYEOF

cleanup
rm -f overlap.txt celerybeat-schedule*
redis-cli -p 6380 -n $DB FLUSHDB > /dev/null 2>&1 || true

"$CELERY" -A pw worker -c 2 -l INFO --logfile=w3.log --pidfile=w3.pid --detach > /dev/null 2>&1 || true
sleep 4
"$CELERY" -A pw beat -l INFO --schedule=celerybeat-schedule \
    --logfile=beat.log --pidfile=beat.pid --detach > /dev/null 2>&1 || true

echo "beat 已启动，观察 26 秒（每 3 秒调度，任务 8 秒）..."
sleep 26

pkill -9 -f 'celery -A pw beat' > /dev/null 2>&1 || true
sleep 1

echo
echo "--- overlap.txt（START/END 交错说明重叠）---"
if [ -f overlap.txt ]; then
  sort -n overlap.txt
  echo
  echo "START 次数 = $(grep -c START overlap.txt)"
  echo "END   次数 = $(grep -c END overlap.txt)"
else
  echo "(无记录)"
fi

cleanup
echo
echo "==============================================="
echo "补验结束"
exit 0

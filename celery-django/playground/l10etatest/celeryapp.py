"""验证：任务执行时长 > visibility_timeout 时，是否会被重复投递执行。

这是「决策 2」真正依赖的风险场景——不是 countdown 等待，而是执行耗时。
"""
import time
from celery import Celery

app = Celery('etatest', broker='redis://localhost:6380/3')
app.conf.update(
    task_acks_late=True,
    broker_transport_options={'visibility_timeout': 5},   # 5 秒
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    result_backend='redis://localhost:6380/4',
    result_expires=120,
)


@app.task(bind=True)
def long_run_task(self, label, seconds):
    """执行时长超过 visibility_timeout 的任务。"""
    ts = time.strftime('%H:%M:%S')
    with open('/tmp/l10_eta_exec.log', 'a') as f:
        f.write(f'{ts} START {label} seconds={seconds} id={self.request.id[:8]}\n')
    time.sleep(seconds)
    with open('/tmp/l10_eta_exec.log', 'a') as f:
        f.write(f'{ts} DONE  {label} id={self.request.id[:8]}\n')
    return {'label': label, 'slept': seconds}

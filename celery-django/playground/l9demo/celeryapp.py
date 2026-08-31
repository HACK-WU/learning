"""
课 9 并发模型验证用的 Celery app。
刻意不用 Django：本课要验证的是 worker 的并发与停机行为，与 Web 框架无关。
broker / backend 都用 6380 上那个干净实例。
"""
from celery import Celery

app = Celery(
    'l9demo',
    broker='redis://localhost:6380/0',
    backend='redis://localhost:6380/1',
)

app.conf.update(
    task_serializer='json',
    result_serializer='json',
    accept_content=['json'],
    timezone='Asia/Shanghai',
    # 让 worker 启动时自动导入任务模块（等价于 Django 里的 autodiscover_tasks）
    imports=['tasks'],
    # 只发信号用得到，本课实测会显式设置
    worker_send_task_events=False,
)

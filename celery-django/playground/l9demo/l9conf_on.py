"""课 9 验证：开启 soft shutdown 的配置模块（通过 --include 注入 worker）。"""
from celeryapp import app

app.conf.worker_soft_shutdown_timeout = 15.0
app.conf.worker_enable_soft_shutdown_on_idle = True
app.conf.task_acks_late = True

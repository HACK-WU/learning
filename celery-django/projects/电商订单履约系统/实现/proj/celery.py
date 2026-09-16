"""
Celery 应用配置（知识点 4：Django 标准集成姿势）

关键点：
- 用 CELERY_ 命名空间从 Django settings 读取配置（Django 官方推荐姿势）
- autodiscover_tasks 自动发现各 app 下的 tasks.py
- 信号钩子把 task_id 打进每条日志（知识点 19：可观测性）
"""
import logging
import os

from celery import Celery
from celery.signals import task_failure, task_postrun, task_prerun

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proj.settings')

# ⭐ 日志目录必须存在，否则 RotatingFileHandler 会在 Django 启动时直接崩
#   （真实踩坑：用相对路径 'logs/celery.log' 而目录不存在 →
#    ValueError: Unable to configure handler 'celery_file'）
LOG_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'logs')
os.makedirs(LOG_DIR, exist_ok=True)

app = Celery('proj')
# namespace='CELERY' 表示只读取 settings.py 里以 CELERY_ 开头的配置
app.config_from_object('django.conf:settings', namespace='CELERY')
# 自动发现 INSTALLED_APPS 里的 tasks.py
app.autodiscover_tasks()

logger = logging.getLogger('celery.tasks')


# ============================================================
# 可观测性：三个信号钩子（知识点 19）
# 作用：每条日志都带 task_id，出事后能串联全链路
# ============================================================

@task_prerun.connect
def log_task_start(sender=None, task_id=None, **kwargs):
    """任务开始：记录 task_id + 任务名 + 参数"""
    logger.info('[task_start] task_id=%s name=%s args=%s kwargs=%s',
                task_id, sender.name, sender.request.args, sender.request.kwargs)


@task_postrun.connect
def log_task_end(sender=None, task_id=None, state=None, **kwargs):
    """任务结束：记录 task_id + 状态"""
    logger.info('[task_end] task_id=%s name=%s state=%s', task_id, sender.name, state)

    # 知识点 13：释放数据库连接，防内存泄漏（课 6）
    from django.db import connection
    connection.close()


@task_failure.connect
def log_task_failure(sender=None, task_id=None, exception=None, args=None,
                     task_kwargs=None, **extra):
    """任务失败：记录 task_id + 异常（这里就是接告警的地方）

    ⚠️ 触发时机：只在【最终失败】时触发（重试耗尽，或直接失败且没配重试）。
       每次 autoretry 重试都不会走到这里 —— 所以这里是落死信的正确位置。
    """
    logger.error('[task_failed] task_id=%s name=%s exc=%s',
                 task_id, sender.name, exception, exc_info=True)
    # 生产环境在这里接告警：发送钉钉/企业微信/邮件
    # notify_alert(f'Celery 任务失败 task_id={task_id} name={sender.name}')

    # ⭐ 死信兜底（课 5 知识点 2.5）：重试耗尽的消息必须有地方可查、可重放
    #    单独抽到 proj/dlq.py，方便单独测试与复用
    try:
        from proj.dlq import capture_dead_letter_record
        capture_dead_letter_record(
            sender=sender, task_id=task_id, exception=exception,
            args=args, kwargs=task_kwargs,
        )
    except Exception as exc:      # ⚠️ 兜底逻辑绝不能把主流程搞崩
        logger.exception('[DLQ] 死信入库失败（已忽略，不影响主流程）: %s', exc)


@app.task(bind=True, ignore_result=True)
def debug_task(self):
    """调试用：打印当前请求上下文"""
    print(f'Request: {self.request!r}')

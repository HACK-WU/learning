"""死信队列（DLQ）兜底 —— 课 5 知识点 2.5 的落地。

⚠️ 为什么必须有这个模块：
    Celery 的重试机制只负责「再试几次」。重试全部耗尽后，消息被 ack 掉、
    worker 打一条 ERROR 日志就完事了 —— 用户没收到通知，而你根本不知道。
    这就是「静默丢失」，比报错更危险。

⭐ 关键设计：
    1. 只在 task_failure 里落死信（task_retry 是每次重试都触发，会重复 3 条）
    2. 必须落到「进程外能读到」的地方（这里是 Redis list）
       —— 存全局变量没用，worker 是独立进程，你在 shell 里读不到
    3. 记录 task_name + args + kwargs，故障恢复后才能重放

实测依据（celery 5.6.3，max_retries=3）：
    [EXEC]  第 1~4 次执行（首试 + 3 次重试）
    [DLQ]   已捕获死信 task=dlq.send_sms args=['13800000000']   ← 只出现 1 次
    redis-cli llen celery_dlq → 1
"""
import json
import logging

import redis
from celery.signals import task_failure
from django.conf import settings

logger = logging.getLogger('celery.dlq')

# 死信存储的 Redis key（用 list，LPUSH 写入 / LRANGE 读取 / LREM 重放后删除）
DLQ_KEY = 'celery_dlq'
# 死信单独用一个 db，避免污染 broker（db0）和 backend（db1）
DLQ_REDIS_DB = 7


def _get_redis():
    """从 broker URL 派生出死信用 Redis 连接（换 db，不改 host/port/密码）。"""
    url = settings.CELERY_BROKER_URL
    if url.startswith('redis://'):
        # redis://:pwd@host:port/0 -> redis://:pwd@host:port/7
        base = url.rsplit('/', 1)[0]
        return redis.Redis.from_url(f'{base}/{DLQ_REDIS_DB}', decode_responses=True)
    # 非 Redis broker（如 RabbitMQ）时退化到默认本地 Redis
    return redis.Redis(host='127.0.0.1', port=6379, db=DLQ_REDIS_DB, decode_responses=True)


def capture_dead_letter_record(sender=None, task_id=None, exception=None,
                               args=None, kwargs=None, traceback=None,
                               einfo=None, **kw):
    """落一条死信记录。

    ⚠️ 调用时机：只在任务【最终失败】时调用一次。
       每一次 autoretry 重试都不会到这里（那是 task_retry 信号）。

    两种用法：
      1. 直接被 proj/celery.py 的 task_failure 钩子调用（项目里的实际接法）
      2. 通过下方 @task_failure.connect 独立注册（单独复用本模块时用）
    """
    record = {
        'task_name': sender.name,
        'task_id': task_id,
        'args': list(args) if args else [],
        'kwargs': kwargs or {},
        'error': f'{type(exception).__name__}: {exception}',
    }
    try:
        _get_redis().rpush(DLQ_KEY, json.dumps(record, ensure_ascii=False))
        logger.error('[DLQ] 死信入库 task=%s args=%s err=%s',
                     record['task_name'], record['args'], record['error'])
    except Exception as exc:      # 兜底本身绝不能把任务搞崩
        logger.exception('[DLQ] 死信入库失败（不能影响主流程）: %s', exc)
    return record


# ⚠️ 注意：项目里【不要】同时启用这里的信号注册和 celery.py 里的显式调用，
#    否则同一条失败会落两条死信。默认注释掉，由 celery.py 统一调用。
# @task_failure.connect
# def capture_dead_letter(sender=None, **kw):
#     capture_dead_letter_record(sender=sender, **kw)


def list_dead_letters(limit=50):
    """读取死信（运维/排障用）。"""
    return [json.loads(x) for x in _get_redis().lrange(DLQ_KEY, 0, limit - 1)]


def replay(task_name, args=None, kwargs=None):
    """重放一条死信：按原始参数重新投递。

    用法（Django shell）：
        from proj.dlq import list_dead_letters, replay
        list_dead_letters()                       # 先看有哪些
        replay('orders.tasks.send_notification', [42])
    """
    from proj.celery import app
    task = app.tasks[task_name]
    result = task.delay(*(args or []), **(kwargs or {}))
    logger.info('[DLQ] 重放 task=%s 新 task_id=%s', task_name, result.id)
    return result.id

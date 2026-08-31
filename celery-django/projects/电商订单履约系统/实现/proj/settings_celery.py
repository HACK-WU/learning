"""
Celery 生产配置基线（知识点 8/10/19/21/22）

所有配置都用 CELERY_ 前缀，与 celery.py 里的 namespace='CELERY' 对应。

⚠️ 实测提醒（课 9/课 10 血的教训）：
- CELERY_WORKER_SOFT_SHUTDOWN_TIMEOUT 必须写在这里（settings.py），
  通过环境变量注入会【静默失效】—— 实测 worker 读到的仍是 0.0
- REMAP_SIGTERM 反过来：只能是环境变量，写在这里无效
"""
import os

# ============================================================
# 🔴 序列化安全（知识点 21：禁 pickle，防 RCE）
# ============================================================
# ⭐ 三个必须一起配，缺一不可：
#    task_serializer   只决定"发出去用什么格式"
#    accept_content    才决定"worker 接受什么格式" ← 这才是真正的防线
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json']          # ⭐ 绝不能包含 'pickle'

# ============================================================
# Broker 与 Backend
# ============================================================
# 从环境变量读，不要硬编码密码（知识点 21）
CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://:yourpassword@localhost:6380/0')
CELERY_RESULT_BACKEND = os.environ.get('CELERY_RESULT_BACKEND', 'redis://:yourpassword@localhost:6380/1')

# Redis broker 的 visibility_timeout 必须 > 最长任务执行时间
# ⚠️ 实测补充：新版 kombu 有续期机制，但这个值仍建议留足余量
CELERY_BROKER_TRANSPORT_OPTIONS = {
    'visibility_timeout': 3600,      # 1 小时，要大于最长的对账任务
}

# ============================================================
# 🔴 可靠性（知识点 8：确认机制）
# ============================================================
CELERY_TASK_ACKS_LATE = True                  # 执行完才 ack（保不丢）
CELERY_TASK_REJECT_ON_WORKER_LOST = True      # worker 被强杀时任务重新入队

# 结果过期时间（知识点 22：不设会永久堆积）
# 实测：300 个任务 = 300 条 key，328 bytes/条
CELERY_RESULT_EXPIRES = 3600

# ============================================================
# 🔴 超时保护（知识点 20：防僵尸任务）
# ============================================================
# 实测：不配超时 → 2 个卡死任务占满槽位，快任务 6 秒拿不到结果
# 实测：配了 soft_time_limit=3 → 3.1 秒自动解除，槽位释放
CELERY_TASK_SOFT_TIME_LIMIT = 60             # 软超时：留时间清理
CELERY_TASK_TIME_LIMIT = 120                 # 硬超时：兜底硬杀

# ============================================================
# 并发与进程（知识点 17）
# ============================================================
CELERY_WORKER_PREFETCH_MULTIPLIER = 1        # 长任务场景保证公平分发
CELERY_WORKER_MAX_TASKS_PER_CHILD = 1000     # 防内存泄漏（课 9 实测有效）
CELERY_WORKER_MAX_MEMORY_PER_CHILD = 200000  # 200MB（单位 KiB）

# ============================================================
# 优雅停机（知识点 18）
# ============================================================
# ⚠️ 必须写在 settings.py！环境变量注入会静默失效（课 9 实测）
CELERY_WORKER_SOFT_SHUTDOWN_TIMEOUT = 15.0
CELERY_WORKER_ENABLE_SOFT_SHUTDOWN_ON_IDLE = True

# ============================================================
# events 与可观测性（知识点 19）
# ============================================================
# ⭐ 不开这个，Flower 的任务列表就是空白（课 10 实测：10 行心跳 vs 27 行事件）
CELERY_WORKER_SEND_TASK_EVENTS = True
CELERY_EVENT_QUEUE_TTL = 5.0                 # 事件消息 5s 过期，防堆积
CELERY_EVENT_QUEUE_EXPIRES = 60.0            # 事件队列空闲 60s 删除

# ============================================================
# 队列路由（决策 1 / 知识点 16：队列隔离）
# ============================================================
# 课 9 实测：20 慢 + 5 快，不隔离时快任务等 10.03s，隔离后 0.51s
CELERY_TASK_ROUTES = {
    # ⭐ 编排入口也要配路由！漏了它就进 default 队列，整个编排不会开始
    'orders.tasks.fulfill_order': {'queue': 'fast'},
    'orders.tasks.send_notification': {'queue': 'fast'},
    'orders.tasks.issue_coupon': {'queue': 'fast'},        # ⭐ 别漏，漏了就进 default 队列
    'orders.tasks.heartbeat': {'queue': 'fast'},
    'orders.tasks.close_order': {'queue': 'slow'},
    'orders.tasks.write_reconciliation': {'queue': 'slow'},
    'orders.tasks.scan_timeout_orders': {'queue': 'slow'},
}

# ⚠️ 真实踩坑记录：初版漏配了 issue_coupon，它进了 default 队列，
#    而 worker 只消费 fast/slow → chord 的 header 永远凑不齐 → chord 永不完成 → 超时
#    排障手段：celery -A proj inspect active_queues 看每个 worker 在消费哪些队列

# ⚠️ 真实踩坑（本机实测）：编排的【入口任务】如果漏配路由，会进 default 队列，
#    而 worker 只消费 fast/slow → 整个编排根本没开始 → 静默挂死（不报错，就是一直等）
#
#    实测：worker -Q fast,slow  → chord 超时，default 队列积压 1 条
#    取证：解出积压消息内容，task = orders.tasks.fulfill_order（编排入口本身）
#    修复：给 fulfill_order 补上路由后，仍用 -Q fast,slow（不含 default）→ chord 跑通 ✅
#
# ❗纠错（2026-08-31）：这里原先写的是"chord 的解锁任务会走 default 队列"，**这是错的**。
#    Redis backend 有原生 chord 协调（ZADD/ZCOUNT 计数，最后一个成员完成时直接触发回调），
#    根本不会产生 chord_unlock 轮询任务 —— 修复后实测日志里 chord_unlock 出现 0 次。
#    真正的根因是 fulfill_order 自己漏配了路由。详见设计决策「决策 4（已修正）」。
CELERY_TASK_DEFAULT_QUEUE = 'default'

# ============================================================
# 时区（Django 项目必配，知识点 14）
# ============================================================
CELERY_TIMEZONE = 'Asia/Shanghai'
CELERY_ENABLE_UTC = True
CELERY_BEAT_SCHEDULE = {
    # ⭐ 决策 2：beat 轮询扫描超时订单（而非 ETA 延迟任务）
    # 理由：ETA 方案的 revoke 有竞态（实测拦不住已开跑的任务）
    'scan-timeout-orders': {
        'task': 'orders.tasks.scan_timeout_orders',
        'schedule': 30.0,                    # 每 30 秒扫一次
    },
    # 知识点 14：beat 挂了是静默的，必须有心跳监控
    'beat-heartbeat': {
        'task': 'orders.tasks.heartbeat',
        'schedule': 60.0,                    # 每 60 秒一次
    },
}

# ============================================================
# 日志配置（知识点 19：task_id 串联）
# ============================================================
# ⭐ 日志目录必须存在，否则 RotatingFileHandler 会让 Django 启动崩溃
#   这里用 BASE_DIR 算绝对路径，与 proj/celery.py 的 LOG_DIR 保持一致
import os as _os
LOG_DIR = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))), 'logs')
_os.makedirs(LOG_DIR, exist_ok=True)

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '[{asctime}] {levelname} [{processName}] {name} - {message}',
            'style': '{',
        },
    },
    'handlers': {
        'celery_file': {
            'level': 'INFO',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.path.join(LOG_DIR, 'celery.log'),
            'maxBytes': 100 * 1024 * 1024,     # 100MB 轮转
            'backupCount': 5,
            'formatter': 'verbose',
        },
    },
    'loggers': {
        'celery.tasks': {
            'handlers': ['celery_file'],
            'level': 'INFO',
            'propagate': False,
        },
    },
}

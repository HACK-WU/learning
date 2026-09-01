# -*- coding: utf-8 -*-
"""配置与常量（综合实战项目：订单履约消息系统）

知识点对照：
- 课 3/课 11：连接参数与端口（三节点集群 5681/5682/5683）
- 课 9：心跳设置（pika 是客户端值优先，不是"取较小值"）
- 课 5：队列 arguments（DLX / delivery-limit / delayed-retry）
"""
import os

# ============ 连接配置 ============
# 三节点集群（课 11 搭建）：rmq1/rmq2/rmq3 映射宿主 5681/5682/5683
# 连任意一个节点都能访问全部 quorum 队列（非 leader 会转发给 leader）
NODES = [
    ('localhost', 5681),
    ('localhost', 5682),
    ('localhost', 5683),
]

USER = os.getenv('RMQ_USER', 'learn')
PASS = os.getenv('RMQ_PASS', 'learn123')
VHOST = '/'

# 心跳（课 9）：pika 是"客户端填了值就无条件优先"，
# 服务端默认 60，客户端请求 600 → 协商结果就是 600，不会被压缩。
# 设大一点是为了避免短暂网络抖动误判断连；代价是真实断线时要等 2×600s 才感知。
HEARTBEAT = 600

#  blocked_connection_timeout：连不上/被阻塞时的超时（秒）
BLOCKED_TIMEOUT = 300

# ============ 交换机 ============
# 课 4：topic 交换机按事件类型路由
EX_ORDER = 'order.topic'          # 订单事件主交换机
EX_NOTIFY = 'notify.fanout'       # 通知广播（课 12 发布订阅模式）
EX_DLX = 'order.dlx'              # 死信交换机

# ============ 队列 ============
# 决策 2：主链路 quorum（高可用），旁路通知 classic（省资源）
Q_STOCK = 'order.stock'           # 库存：quorum（同步 RPC 的服务端消费）
Q_FULFILL_VIP = 'order.fulfill.vip'      # 发货 VIP：quorum（决策 5）
Q_FULFILL_NORMAL = 'order.fulfill.normal'  # 发货普通：quorum
Q_SMS = 'notify.sms'              # 短信：classic（丢了影响小）

# 死信队列
Q_DLQ = 'order.dlq'               # 主死信队列
Q_SMS_DLQ = 'notify.sms.dlq'      # 短信死信队列

# ============ 路由键 ============
RK_ORDER_CREATED = 'order.created'
RK_STOCK_DONE = 'order.stock.done'
RK_STOCK_FAILED = 'order.stock.failed'
RK_FULFILL_VIP = 'order.fulfill.vip'
RK_FULFILL_NORMAL = 'order.fulfill.normal'

# ============ 队列参数（课 5 / 课 7 / 课 10）============
# 重试策略：min 1s、max 30s，指数退避
RETRY_MIN_MS = 1000
RETRY_MAX_MS = 30000

# 交付上限：超过 delivery-limit 次"投递失败"后转死信
# ⚠️ 只有 reject 会推进 delivery-count，nack 不会（课 10 + 本项目探测）
DELIVERY_LIMIT = 3

# 消费者超时（4.3 新增，讲义未覆盖）：
# 消费者取到消息后超过该时长未 ack → broker 取消该消费者、消息退回队列。
# 本项目实测（p3-probe-timeout.py）：设 3000ms → 3 秒后收到取消通知，
# 消息重新可被取到且 redelivered=True。
# 取值权衡：太短会误杀正常的慢业务，太长则卡死的消息被占用过久。
# 本项目业务处理都是毫秒级，给 30 秒留足余量。
CONSUMER_TIMEOUT_MS = 30000


def quorum_args(dlx=None, dlx_rk=None, delivery_limit=DELIVERY_LIMIT,
                consumer_timeout=CONSUMER_TIMEOUT_MS):
    """生成 quorum 队列的 arguments。

    知识点：
    - 课 5：x-queue-type 指定队列类型
    - 课 7：x-dead-letter-exchange 死信兜底
    - 课 10：x-delayed-retry-* 是 4.3 原生能力（无需插件）
             x-delivery-limit 触发死信的阈值
    - 4.3 新增：x-consumer-timeout 消费者超时（讲义未覆盖，本项目实测补充）

    注意：quorum 队列**不接受** x-max-priority（课 10 实测 12 个取值全被拒）。

    关于 x-consumer-timeout（本项目 p3-probe-timeout.py 实测）：
      消费者取到消息后超过该时长不 ack，broker 会**取消该消费者**
      并把消息退回队列（实测：设 3000ms → 3 秒后收到 cancel 通知，
      消息重新可被取到且 redelivered=True）。
      价值：防止"消费者卡死但连接还在"导致消息被无限期占用。
      官方说明：4.3 起超时由 quorum 队列自己评估，classic/stream 不再评估。
    """
    args = {'x-queue-type': 'quorum'}
    if consumer_timeout:
        args['x-consumer-timeout'] = consumer_timeout
    if dlx:
        args['x-dead-letter-exchange'] = dlx
        if dlx_rk:
            args['x-dead-letter-routing-key'] = dlx_rk
    if delivery_limit:
        args['x-delivery-limit'] = delivery_limit
        # 延迟退避：只有配了 delivery-limit 才配重试，否则会无限重试
        args['x-delayed-retry-type'] = 'all'
        args['x-delayed-retry-min'] = RETRY_MIN_MS
        args['x-delayed-retry-max'] = RETRY_MAX_MS
    return args


def classic_args(dlx=None):
    """生成 classic 队列的 arguments（旁路通知用）。

    决策 2：短信用 classic —— 不值得为它付 quorum 的 3.7 倍写代价与 3 倍内存。

    ⚠️ 实测发现（本项目 p3-probe-classic.py，课 10 讲义未覆盖）：
    classic 队列**不接受** x-delivery-limit 与全部 x-delayed-retry-* 参数：
        invalid arg 'x-delivery-limit' for queue ... of queue type rabbit_classic_queue
        invalid arg 'x-delayed-retry-type' for queue ... of queue type rabbit_classic_queue
    这**两个参数是 quorum 专属**。classic 只接受 DLX / max-length / TTL 等传统参数。

    后果：短信队列**不能靠 broker 做重试退避与超限死信**，
    必须自己在应用层计数（见 consumer.py 的 AppLevelRetryMixin）。
    这正是"选 classic 省下的资源，要用代码复杂度还回来"的地方。
    """
    args = {'x-queue-type': 'classic'}
    if dlx:
        args['x-dead-letter-exchange'] = dlx
    return args


# ============ 预取值（决策 4）============
# 主链路 10：崩溃最多丢 10 条未确认消息，吞吐是 prefetch=1 的 5.5 倍
# 短信 50：无顺序要求、量大、单条快，为吞吐让渡
PREFETCH_MAIN = 10
PREFETCH_SMS = 50

# ============ Direct Reply-To（课 12）============
# 伪队列名，用于同步 RPC
REPLY_QUEUE = 'amq.rabbitmq.reply-to'

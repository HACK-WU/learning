"""订单相关的异步任务。

本文是【决策 2】【决策 3】的落地：
- 决策 2：超时关单用 beat 轮询（scan_timeout_orders），而不是 ETA 延迟任务
- 决策 3：关单用 CAS 状态机做幂等，而不是 Redis SET NX

⚠️ 所有任务都遵循两条铁律（课 6）：
  1. 参数只传 id，不传 ORM 对象（对象序列化后会过期）
  2. 用 filter().update() 返回影响行数判断幂等，而不是先查后改
"""
import logging
from datetime import timedelta

from celery import chord, shared_task
from django.db import transaction
from django.db.models import F
from django.utils import timezone

from .models import Order, Reconciliation, Stock

logger = logging.getLogger('celery.tasks')

# 订单超时时间：15 分钟
ORDER_TIMEOUT_MINUTES = 15


# ============================================================
# 决策 2：超时关单 —— beat 轮询方案
# ============================================================

@shared_task(
    name='orders.tasks.scan_timeout_orders',
    bind=True,
    # 关单结果不需要存（知识点 22：不必要的结果不存，防 backend 撑爆）
    ignore_result=True,
    soft_time_limit=60,
    time_limit=120,
)
def scan_timeout_orders(self):
    """扫描超时未支付的订单并关闭（beat 每 30 秒调用一次）。

    ⭐ 为什么用轮询而不是 ETA 延迟任务（决策 2）：
      实测发现 ETA 方案的 revoke 有竞态 —— 任务一旦开跑就拦不住
      （l10-test-cancel.sh：DONE 次数 = 1）。用户第 14:59 支付、
      任务同时开跑，已支付的订单会被误关。
      轮询方案的"撤销"是天然免费的：订单一支付就不再满足扫描条件。
    """
    deadline = timezone.now() - timedelta(minutes=ORDER_TIMEOUT_MINUTES)

    # 只查 id，避免大对象传输（课 6）
    timeout_ids = list(
        Order.objects.filter(status=Order.STATUS_PENDING, created_at__lt=deadline)
        .values_list('id', flat=True)[:1000]      # 限量，防一次扫太多
    )

    if not timeout_ids:
        return {'scanned': 0}

    logger.info('[scan_timeout] 发现 %d 个超时订单', len(timeout_ids))

    closed_count = 0
    for order_id in timeout_ids:
        # 逐个投递关单任务（而不是在循环里同步执行，避免单个慢订单拖慢整轮扫描）
        close_order.delay(order_id)
        closed_count += 1

    return {'scanned': closed_count}


@shared_task(
    name='orders.tasks.close_order',
    bind=True,
    # 关单不需要返回值 → 不存结果（知识点 22）
    ignore_result=True,
    soft_time_limit=30,
    time_limit=60,
    # 知识点 10：外部依赖失败自动重试（本任务主要是 DB 操作，重试保守些）
    autoretry_for=(Exception,),
    retry_backoff=2,
    retry_kwargs={'max_retries': 3},
)
def close_order(self, order_id):
    """关闭单个超时订单 + 回滚库存。

    ⭐⭐ 决策 3：用 CAS 状态机做幂等（而不是 Redis SET NX）

    实测依据（l10-test-idempotent.sh）：
      无幂等：执行 3 次 → 库存 10→13（多回滚 2 次，超卖）
      CAS   ：执行 3 次 → 返回值 [1, 0, 0]，库存 11 ✅

    ⚠️ 幂等为什么不能省（l10-test-kill.sh 实测）：
      worker 被执行中的任务 SIGKILL 后，任务被重新投递执行
      → START 次数 = 2（重复执行真实存在）
      → acks_late 保住了"不丢"，代价是"可能重复"
    """
    try:
        with transaction.atomic():
            # ⭐⭐ CAS 核心：只有 PENDING 才能变 CLOSED
            # filter().update() 返回影响行数：1=真的关了，0=已被别人关了/已支付
            updated = Order.objects.filter(
                id=order_id,
                status=Order.STATUS_PENDING,      # ⭐ 这个条件就是幂等锁
            ).update(
                status=Order.STATUS_CLOSED,
                closed_at=timezone.now(),
            )

            if updated == 0:
                # 说明订单已支付或已被关闭 → 什么都不做，直接返回
                logger.info(
                    '[close_order] order_id=%s 状态已变更，跳过（幂等生效）',
                    order_id,
                )
                return {'closed': False, 'reason': 'already_processed'}

            # 只有真的关单了，才回滚库存
            # ⭐ 用 F() 表达式在 DB 层原子自增，避免读-改-写的竞态
            order = Order.objects.get(id=order_id)
            Stock.objects.filter(sku=order.sku).update(quantity=F('quantity') + order.quantity)

            logger.info('[close_order] order_id=%s 已关闭，库存已回滚', order_id)
            return {'closed': True}
    except Order.DoesNotExist:
        logger.warning('[close_order] order_id=%s 不存在', order_id)
        return {'closed': False, 'reason': 'not_found'}


# ============================================================
# 履约编排（知识点 15：canvas chord）
# ============================================================

@shared_task(
    name='orders.tasks.fulfill_order',
    bind=True,
    soft_time_limit=60,
    time_limit=120,
)
def fulfill_order(self, order_id):
    """支付成功后的履约编排：并行发券 + 通知，都完成后汇总写对账。

    知识点 15：用 chord（并行执行 + 汇总回调）
      header = group(发券, 通知)  ← 并行
      body   = 汇总写对账          ← 两者都完成后才执行

    为什么不用 chain：发券和通知互不依赖，并行能省一半时间
    为什么不用 group：需要在两者都完成后写对账，group 没有汇总回调
    """
    callback = write_reconciliation.s(order_id)
    header = [
        issue_coupon.s(order_id),
        send_notification.s(order_id),
    ]
    result = chord(header)(callback)
    return {'fulfillment_id': str(result.id)}


@shared_task(
    name='orders.tasks.send_notification',
    bind=True,
    # 知识点 10：外部 HTTP 调用必须重试 + 退避 + 超时
    autoretry_for=(ConnectionError, TimeoutError, OSError),
    retry_backoff=2,              # 指数退避：2s, 4s, 8s
    retry_backoff_max=60,
    retry_kwargs={'max_retries': 5},
    soft_time_limit=10,
    time_limit=20,
)
def send_notification(self, order_id):
    """发送支付成功通知（快任务，进 fast 队列）。

    ⚠️ 必须有 timeout！没有 timeout 的 HTTP 调用会永久占用 worker 槽位
    （课 10 实测：2 个卡死任务就能让快任务 6 秒排不上）

    ⭐ 教学说明：外部短信服务用「可注入」设计
       - 默认走 MOCK 模式（不发真实请求），保证 demo 开箱即跑通
       - 生产环境设环境变量 SMS_API_URL 即切换为真实调用
       这样既保留了真实的重试/超时语义，又不需要你先去申请短信服务密钥
    """
    import os

    import requests

    order = Order.objects.get(id=order_id)
    api_url = os.environ.get('SMS_API_URL')

    if not api_url:
        # 🎭 MOCK 模式：不走网络，直接返回成功
        logger.info('[send_notification] MOCK 模式 order_id=%s（设 SMS_API_URL 可切真实调用）', order_id)
        return {'notified': True, 'order_id': order_id, 'mock': True}

    # 真实调用：⭐ timeout 参数不能省，否则一个卡住的请求就是僵尸任务
    resp = requests.post(
        api_url,
        json={'user_id': order.user_id, 'order_id': order_id},
        timeout=5,                # 连接 5s + 读取 5s
    )
    resp.raise_for_status()
    return {'notified': True, 'order_id': order_id, 'mock': False}


@shared_task(
    name='orders.tasks.issue_coupon',
    bind=True,
    autoretry_for=(ConnectionError, TimeoutError),
    retry_backoff=2,
    retry_kwargs={'max_retries': 3},
    soft_time_limit=10,
    time_limit=20,
)
def issue_coupon(self, order_id):
    """发放优惠券（快任务，进 fast 队列）。"""
    # 实际业务：调优惠券服务
    logger.info('[issue_coupon] order_id=%s 发券成功', order_id)
    return {'coupon_issued': True, 'order_id': order_id}


@shared_task(
    name='orders.tasks.write_reconciliation',
    bind=True,
    soft_time_limit=120,
    time_limit=180,
    # ⭐⭐ 这里【不能】设 ignore_result=True！
    #     chord 的 header 任务必须保存结果，否则回调永远不触发（chord 静默挂死）
    #     官方文档原话："Tasks used within a chord must not ignore their results."
    #     ⚠️ 这是本课最反直觉的一条：课 10 教"不需要结果就不存"，但 chord 是例外 ——
    #        chord 依赖结果计数来判断"header 是否都完成了"
    ignore_result=False,
)
def write_reconciliation(self, results, order_id):
    """chord 的汇总回调：把并行任务的结果写入对账表。

    ⭐ chord 回调的签名：第一个参数是 header 的结果列表
      results = [issue_coupon 的返回值, send_notification 的返回值]

    ⚠️ 这是【慢任务】（每件 2 秒级），所以路由到 slow 队列（决策 1）
    """
    coupon_result, notify_result = results[0], results[1]

    Reconciliation.objects.create(
        order_id=order_id,
        coupon_ok=bool(coupon_result.get('coupon_issued')),
        notify_ok=bool(notify_result.get('notified')),
    )
    logger.info('[reconciliation] order_id=%s 对账完成', order_id)
    return {'reconciled': True, 'order_id': order_id}


# ============================================================
# 知识点 14：beat 心跳监控（beat 挂了是静默的！）
# ============================================================

@shared_task(
    name='orders.tasks.heartbeat',
    bind=True,
    ignore_result=True,
)
def heartbeat(self):
    """beat 存活心跳（每 60 秒一次）。

    ⭐ 为什么需要：beat 挂掉不会有任何报错，只是定时任务不再触发。
    没有心跳的话，关单功能会【静默停止】，直到用户投诉才发现（课 7）。
    """
    logger.info('[heartbeat] beat alive at %s', timezone.now().isoformat())
    # 生产环境：往监控系统上报一个时间戳，超过 3 分钟没更新就告警
    return {'alive': True}

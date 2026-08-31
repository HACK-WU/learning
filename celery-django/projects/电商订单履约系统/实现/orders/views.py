"""订单视图。

⭐ 本文件最关键的一行是 transaction.on_commit（知识点 11）
   这是课 6 讲的核心坑，也是反例对照里第 1 条对比的正面示范
"""
import logging

from celery.result import AsyncResult
from django.db import transaction
from django.http import JsonResponse
from django.views.decorators.http import require_POST

from proj.celery import app as celery_app

from .models import Order, Stock
from .tasks import fulfill_order

logger = logging.getLogger(__name__)


@require_POST
@transaction.atomic
def create_order(request):
    """创建订单：扣库存 + 落库。

    ⭐ 决策 2 落地：这里【不发】关单任务！
      关单由 beat 每 30 秒轮询扫描超时订单完成（tasks.scan_timeout_orders）。
      理由：避免 ETA 方案的 revoke 竞态（实测拦不住已开跑的任务）。
    """
    sku = request.POST.get('sku', 'SKU_DEMO')
    user_id = request.user.id if request.user.is_authenticated else 1

    # 用 select_for_update 加行锁，防并发超卖
    stock = Stock.objects.select_for_update().get(sku=sku)
    if stock.quantity <= 0:
        return JsonResponse({'error': '库存不足'}, status=400)

    stock.quantity -= 1
    stock.save()

    order = Order.objects.create(user_id=user_id, sku=sku, status=Order.STATUS_PENDING)

    return JsonResponse({
        'order_id': order.id,
        'status': order.status,
        'note': '订单已创建，15 分钟内未支付将自动关闭（由 beat 轮询扫描）',
    })


@require_POST
def pay_order(request, order_id):
    """支付订单：改状态 + 触发履约编排。

    ⭐⭐ 知识点 11（课 6 核心坑）：必须在事务【提交后】才发任务
       如果在事务内发，worker 可能比事务提交更快 → 查不到这条订单
       → DoesNotExist 报错；更糟的是事务回滚了但任务已经发出去了
    """
    with transaction.atomic():
        # 同样用 CAS：只有 PENDING 才能变成 PAID
        updated = Order.objects.filter(
            id=order_id, status=Order.STATUS_PENDING
        ).update(status=Order.STATUS_PAID)

        if updated == 0:
            return JsonResponse({'error': '订单状态不允许支付'}, status=400)

        order = Order.objects.get(id=order_id)

        # ⭐⭐ 关键：on_commit 保证任务在事务提交后才发出
        # 反例（错误）：直接在这里 fulfill_order.delay(order_id)
        transaction.on_commit(lambda: _trigger_fulfillment(order_id))

    return JsonResponse({'order_id': order_id, 'status': 'PAID'})


def _trigger_fulfillment(order_id):
    """触发履约编排（只在事务提交后被调用）。

    知识点 15：chord 编排（发券 + 通知并行 → 汇总对账）
    知识点 7：把 task_id 存起来，供前端轮询进度
    """
    result = fulfill_order.delay(order_id)
    Order.objects.filter(id=order_id).update(fulfillment_task_id=result.id)
    logger.info('[fulfillment] order_id=%s task_id=%s 已触发', order_id, result.id)


def fulfillment_progress(request, order_id):
    """查询履约进度（知识点 7：AsyncResult 跨进程重建）。

    ⭐ 关键认知：AsyncResult(task_id) 可以在【另一个进程】里重建，
       只要能拿到同一个 broker/backend 就能查到状态 —— 这是前端轮询方案成立的前提。
    """
    try:
        order = Order.objects.get(id=order_id)
    except Order.DoesNotExist:
        return JsonResponse({'error': '订单不存在'}, status=404)

    if not order.fulfillment_task_id:
        return JsonResponse({'order_id': order_id, 'progress': '未触发履约'})

    # 用 task_id 在 Web 进程里重建 AsyncResult
    result = AsyncResult(order.fulfillment_task_id, app=celery_app)

    return JsonResponse({
        'order_id': order_id,
        'task_id': order.fulfillment_task_id,
        'state': result.state,
        'result': result.result if result.successful() else None,
        'error': str(result.result) if result.failed() else None,
    })

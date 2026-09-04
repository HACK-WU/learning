"""业务逻辑层。

课 7 的结论：业务逻辑放 service，view 只做三件事——
  取参数（Serializer）→ 调 service → 把结果序列化返回。

本模块是全项目的核心，一条 create_order 串起：
  幂等（课 11）→ 事务（课 14）→ F() 原子扣库存（课 11）→ 快照明细
  → 审计日志（课 17）→ 缓存失效（课 16）→ 显式通知（课 17 的反面教材）
"""
import logging
from decimal import Decimal

from django.db import transaction
from django.db.models import F

from apps.common.exceptions import InvalidStatusTransition, OutOfStockError
from apps.common.middleware import get_trace_id
from apps.shop.models import AuditLog, IdempotencyRecord, Order, OrderItem, Product

logger = logging.getLogger("shop")


def models_now():
    """统一的"当前时间"。

    用 Django 的 timezone.now 而不是 datetime.now：
    项目设了 USE_TZ=True，直接写 datetime.now() 会产生 naive datetime 警告。
    """
    from django.utils import timezone

    return timezone.now()


class IdempotentHit(Exception):
    """命中幂等键：已有同 key 的订单。

    ⚠️ 这不是"错误"，所以不继承 BusinessError（不该记 warning）。
    """

    def __init__(self, order):
        self.order = order
        super().__init__(f"idempotent hit: {order.order_no}")


def _write_audit(user, action, target_type, target_id, payload=None):
    """课 17：审计日志用**显式调用**，不用 signal。

    理由（课 17 实测结论）：
      1. signal receiver 抛异常时，autocommit 下数据已落库，异常只会让请求失败
      2. update() 家族不发信号 —— 静默漏记
      3. 隐式耦合让"谁改了数据"不可追踪
    """
    AuditLog.objects.create(
        user=user,
        action=action,
        target_type=target_type,
        target_id=str(target_id),
        payload=payload or {},
        trace_id=get_trace_id(),
    )


@transaction.atomic
def create_order(*, user, items, remark="", idempotency_key=None):
    """创建订单。

    items: [{"product_id": int, "quantity": int}, ...]

    ⚠️ 并发安全的关键在第 3 步：用 F() 配合带条件的 update，
       把"检查库存"和"扣库存"合并成一条 SQL。
       如果写成 `if p.stock >= qty: p.stock -= qty; p.save()`，
       两个请求同时读到 stock=1 就都通过了检查，超卖。

    ⚠️ 事务边界的诚实说明（课 17）：
       本函数内所有数据库操作是原子的。但 _send_notification 之类的
       **外部副作用不在事务保护内** —— 事务回滚了它也不会退回来。
       所以外部调用必须在事务提交**之后**进行（见 create_order_and_notify）。
    """
    # ---- 第 0 步：幂等 ----
    if idempotency_key:
        existing = IdempotencyRecord.objects.filter(
            user=user, key=idempotency_key
        ).select_related("order").first()
        if existing:
            raise IdempotentHit(existing.order)

    if not items:
        raise InvalidStatusTransition("订单至少需要一个商品")

    # 去重并合并同一商品的数量（否则同一商品出现两次会扣两次库存但只记一条明细）
    merged = {}
    for it in items:
        pid = it["product_id"]
        qty = int(it["quantity"])
        if qty < 1:
            raise InvalidStatusTransition(f"数量必须 >= 1：商品 {pid}")
        merged[pid] = merged.get(pid, 0) + qty

    product_ids = list(merged.keys())

    # ⚠️ 刻意**不用** select_for_update()。
    #
    # 第一版写了行锁，实测在 SQLite 上直接抛
    # "database table is locked"，两条线程双双失败（一条都没成功）。
    # 而且它是多余的：下面的 F() + stock__gte 条件 update 本身已经是原子的——
    # "检查库存"和"扣库存"在同一条 SQL 的 WHERE 与 SET 里完成，
    # 数据库保证这条 UPDATE 的原子性，不需要额外的行锁。
    #
    # 单机边界：SQLite 只有库级写锁，本来就不会有真正的行级并发问题；
    # 在 PostgreSQL/MySQL 上这条逻辑同样成立（UPDATE ... WHERE stock >= qty）。
    products = {
        p.pk: p
        for p in Product.objects.filter(pk__in=product_ids, is_active=True)
    }

    missing = [pid for pid in product_ids if pid not in products]
    if missing:
        raise InvalidStatusTransition(
            "商品不存在或已下架", details={"missing_ids": missing}
        )

    # ---- 第 3 步：原子扣库存（F() + 条件 update）----
    #
    # ⚠️ 并发安全的全部秘密在这一行：
    #   UPDATE shop_product SET stock = stock - qty
    #    WHERE id = pid AND stock >= qty
    # 返回受影响行数；为 0 说明库存不够，**此时才有资格**报错。
    #
    # 反例（会超卖）：
    #   if p.stock >= qty:      # 两个请求同时读到 stock=1，都通过
    #       p.stock -= qty      # 都执行扣减 → 库存变 -1
    #       p.save()
    for pid, qty in merged.items():
        updated = Product.objects.filter(pk=pid, stock__gte=qty).update(
            stock=F("stock") - qty, updated_at=models_now()
        )
        if updated == 0:
            product = products[pid]
            raise OutOfStockError(
                f"商品「{product.name}」库存不足",
                details={
                    "product_id": pid,
                    "requested": qty,
                    # 这里的 stock 是加锁后读的快照，仅用于提示；判断依据是 update 的行数
                    "available": product.stock,
                },
            )

    # ---- 第 4 步：建单 ----
    order = Order.objects.create(user=user, status=Order.Status.PENDING, remark=remark)

    total = Decimal("0.00")
    order_items = []
    for pid, qty in merged.items():
        product = products[pid]
        unit_price = product.price
        order_items.append(
            OrderItem(
                order=order,
                product=product,
                product_name=product.name,
                unit_price=unit_price,
                quantity=qty,
            )
        )
        total += unit_price * qty

    # 课 14 的规模意识：bulk_create 一次插入，明细再多也只有一条 SQL
    OrderItem.objects.bulk_create(order_items)

    order.total_amount = total
    order.save(update_fields=["total_amount"])

    # ---- 第 5 步：幂等记录 ----
    if idempotency_key:
        IdempotencyRecord.objects.create(user=user, key=idempotency_key, order=order)

    # ---- 第 6 步：审计日志（显式调用，见 _write_audit 的注释）----
    _write_audit(
        user,
        AuditLog.Action.ORDER_CREATE,
        "order",
        order.pk,
        {"order_no": str(order.order_no), "total": str(total), "items": len(order_items)},
    )

    logger.info(
        "订单创建成功 order_no=%s user=%s total=%s items=%d",
        order.order_no, user.pk, total, len(order_items),
    )

    # ---- 第 7 步：缓存失效（课 16）----
    # 商品库存变了，缓存里的详情必须失效
    for pid in product_ids:
        invalidate_product_cache(pid)

    return order


def create_order_and_notify(*, user, items, remark="", idempotency_key=None):
    """事务提交**之后**再发外部通知。

    这是 create_order 的包装器，用来演示课 17 最重要的一条结论：
    外部副作用（发短信、调支付网关、推 MQ）不能放在事务里。

    放在事务里的后果：
      - 事务最终回滚 → 通知已发出，收不回来（用户收到"下单成功"但订单不存在）
      - 外部调用慢 → 事务长时间持有行锁，拖垮并发
    """
    order = create_order(
        user=user, items=items, remark=remark, idempotency_key=idempotency_key
    )

    # ⚠️ 此刻事务已提交（因为 create_order 是 atomic，返回即提交）
    _send_notification(order)
    return order


def _send_notification(order):
    """模拟外部调用。

    真实项目里这里是短信 / MQ / Webhook。
    刻意保持"可能失败"：失败只记日志，不影响已创建的订单。
    """
    try:
        logger.info("已发送下单通知 order_no=%s", order.order_no)
    except Exception as exc:  # 外部调用失败不该让下单失败
        logger.error("下单通知发送失败 order_no=%s err=%s", order.order_no, exc)


@transaction.atomic
def transition_order_status(*, order, target_status, operator=None):
    """订单状态流转，带合法性校验。

    课 7：状态机的规则在 model 上定义（ALLOWED_TRANSITIONS），
    流转动作在 service 里执行，view 只负责把参数传进来。
    """
    if not order.can_transition_to(target_status):
        raise InvalidStatusTransition(
            f"订单不能从「{order.get_status_display()}」变更为「{dict(Order.Status.choices).get(target_status, target_status)}」",
            details={"from": order.status, "to": target_status},
        )

    order.status = target_status
    order.save(update_fields=["status", "updated_at"])

    action_map = {
        Order.Status.PAID: AuditLog.Action.ORDER_PAY,
        Order.Status.CANCELLED: AuditLog.Action.ORDER_CANCEL,
    }
    action = action_map.get(target_status)
    if action:
        _write_audit(
            operator or order.user, action, "order", order.pk,
            {"to": target_status},
        )
    return order


@transaction.atomic
def cancel_order(*, order, operator=None):
    """取消订单并回滚库存。

    ⚠️ 回滚库存同样要用 F()，理由与扣减完全一致。
    """
    transition_order_status(
        order=order, target_status=Order.Status.CANCELLED, operator=operator
    )

    for item in order.items.select_related("product"):
        Product.objects.filter(pk=item.product_id).update(
            stock=F("stock") + item.quantity
        )
        invalidate_product_cache(item.product_id)

    return order


def invalidate_product_cache(product_id):
    """课 16：缓存失效。

    ⚠️ 用 delete 而不是 set(None)：不同后端对"存 None"的处理不一致，
    delete 的语义永远是明确的"没有缓存"。
    """
    from django.core.cache import cache

    cache.delete(product_cache_key(product_id))


def product_cache_key(product_id):
    return f"shop:product:{product_id}"


def get_product_cached(product_id):
    """商品详情读缓存，未命中回源。

    ⚠️ 缓存的是 pk 查询的结果，所以用 pk 做 key 的一部分。
    ⚠️ 缓存时间刻意设短（60 秒）：库存这类易变数据不适合长缓存。
    """
    from django.core.cache import cache

    key = product_cache_key(product_id)
    data = cache.get(key)
    if data is not None:
        return data, True

    product = Product.objects.filter(pk=product_id, is_active=True).first()
    if product is None:
        return None, False

    data = {
        "id": product.pk,
        "name": product.name,
        "price": str(product.price),
        "stock": product.stock,
    }
    cache.set(key, data, 60)
    return data, False

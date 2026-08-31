"""订单与库存模型。

设计要点：
- Order.status 用有限状态机：PENDING → PAID / CLOSED
  ⭐ 这个状态机是【决策 3 · CAS 幂等】的基础
- 索引 (status, created_at) 是【决策 2 · beat 轮询】的性能关键
"""
from django.db import models


class Order(models.Model):
    """订单"""

    STATUS_PENDING = 'PENDING'   # 待支付
    STATUS_PAID = 'PAID'         # 已支付
    STATUS_CLOSED = 'CLOSED'     # 已关闭（超时未支付 / 手动取消）

    STATUS_CHOICES = [
        (STATUS_PENDING, '待支付'),
        (STATUS_PAID, '已支付'),
        (STATUS_CLOSED, '已关闭'),
    ]

    user_id = models.IntegerField('用户 ID')
    sku = models.CharField('商品 SKU', max_length=64)
    quantity = models.PositiveIntegerField('数量', default=1)
    status = models.CharField(
        '状态', max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING
    )
    created_at = models.DateTimeField('创建时间', auto_now_add=True)
    paid_at = models.DateTimeField('支付时间', null=True, blank=True)
    closed_at = models.DateTimeField('关闭时间', null=True, blank=True)

    # 履约任务 id，供前端轮询进度（知识点 7：AsyncResult 跨进程重建）
    fulfillment_task_id = models.CharField(
        '履约任务 ID', max_length=64, null=True, blank=True
    )

    class Meta:
        db_table = 'orders_order'
        # ⭐ 决策 2 依赖这个索引：beat 每 30 秒扫 status + created_at
        indexes = [
            models.Index(fields=['status', 'created_at'], name='idx_status_created'),
            models.Index(fields=['user_id', 'created_at'], name='idx_user_created'),
        ]

    def __str__(self):
        return f'Order#{self.id} {self.sku} {self.status}'


class Stock(models.Model):
    """库存（简化版，真实场景需要更复杂的扣减逻辑）"""
    sku = models.CharField('商品 SKU', max_length=64, unique=True)
    quantity = models.PositiveIntegerField('库存数量', default=0)

    class Meta:
        db_table = 'orders_stock'

    def __str__(self):
        return f'Stock {self.sku}: {self.quantity}'


class Reconciliation(models.Model):
    """对账记录（chord 汇总后的产物，知识点 15）"""
    order_id = models.IntegerField('订单 ID')
    notify_ok = models.BooleanField('通知是否成功', default=False)
    coupon_ok = models.BooleanField('发券是否成功', default=False)
    created_at = models.DateTimeField('创建时间', auto_now_add=True)

    class Meta:
        db_table = 'orders_reconciliation'

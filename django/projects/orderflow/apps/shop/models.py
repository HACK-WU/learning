"""OrderFlow 的领域模型。

设计取向（来自课 4/12/14）：
  - 约束能下沉到数据库的，一律下沉（CheckConstraint / UniqueConstraint）
    因为 Serializer 层的约束能被裸 SQL、admin、管理命令绕过。
  - 金额用 DecimalField，不用 FloatField（浮点不能表示 0.1，会累积误差）。
  - 状态用 TextChoices，不用裸字符串常量。
"""
import uuid

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class Category(models.Model):
    name = models.CharField("名称", max_length=50, unique=True)
    created_at = models.DateTimeField("创建时间", auto_now_add=True)

    class Meta:
        verbose_name = "分类"
        verbose_name_plural = "分类"
        ordering = ["name"]

    def __str__(self):
        return self.name


class Product(models.Model):
    """商品。

    image 字段承接课 19：上传文件的归属由 STORAGES 决定，
    而不是由 FileField(upload_to=) 单独决定。
    """

    name = models.CharField("名称", max_length=100)
    description = models.TextField("描述", blank=True, default="")
    price = models.DecimalField(
        "单价", max_digits=10, decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    stock = models.PositiveIntegerField("库存", default=0)
    category = models.ForeignKey(
        Category, on_delete=models.PROTECT, related_name="products",
        null=True, blank=True, verbose_name="分类",
    )
    image = models.ImageField("图片", upload_to="products/", blank=True, null=True)
    is_active = models.BooleanField("上架", default=True)
    created_at = models.DateTimeField("创建时间", auto_now_add=True)
    updated_at = models.DateTimeField("更新时间", auto_now=True)

    class Meta:
        verbose_name = "商品"
        verbose_name_plural = "商品"
        ordering = ["-created_at"]
        indexes = [
            # 课 12：列表页默认按"上架 + 时间"筛，复合索引比两个单列索引有效
            models.Index(fields=["is_active", "-created_at"], name="idx_product_active_created"),
        ]
        constraints = [
            # 课 12：价格不能为负——下沉到数据库，裸 SQL 也绕不过
            models.CheckConstraint(
                condition=models.Q(price__gte=0), name="ck_product_price_nonneg"
            ),
        ]

    def __str__(self):
        return self.name


class Order(models.Model):
    """订单。

    order_no 用 UUID 而不是自增 ID：自增 ID 会泄漏业务量（课 10 的安全实践）。
    """

    class Status(models.TextChoices):
        PENDING = "pending", "待支付"
        PAID = "paid", "已支付"
        SHIPPED = "shipped", "已发货"
        CANCELLED = "cancelled", "已取消"

    # 合法状态流转（课 7：业务规则集中定义，而不是散落在 view 里）
    ALLOWED_TRANSITIONS = {
        Status.PENDING: {Status.PAID, Status.CANCELLED},
        Status.PAID: {Status.SHIPPED},
        Status.SHIPPED: set(),
        Status.CANCELLED: set(),
    }

    order_no = models.UUIDField("订单号", default=uuid.uuid4, unique=True, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="orders", verbose_name="下单用户",
    )
    status = models.CharField(
        "状态", max_length=20, choices=Status.choices, default=Status.PENDING
    )
    total_amount = models.DecimalField("订单总额", max_digits=12, decimal_places=2, default=0)
    remark = models.CharField("备注", max_length=200, blank=True, default="")
    created_at = models.DateTimeField("创建时间", auto_now_add=True)
    updated_at = models.DateTimeField("更新时间", auto_now=True)

    class Meta:
        verbose_name = "订单"
        verbose_name_plural = "订单"
        ordering = ["-created_at"]
        indexes = [
            # 列表页按用户查自己的订单 + 按时间倒序
            models.Index(fields=["user", "-created_at"], name="idx_order_user_created"),
            # 后台按状态筛
            models.Index(fields=["status", "-created_at"], name="idx_order_status_created"),
        ]

    def __str__(self):
        return f"{self.order_no} ({self.get_status_display()})"

    def can_transition_to(self, target):
        return target in self.ALLOWED_TRANSITIONS.get(self.status, set())


class OrderItem(models.Model):
    """订单明细。

    冗余存 unit_price 与 product_name：
    商品改价改名字后，历史订单不该跟着变（这是"快照"而非"冗余"）。
    """

    order = models.ForeignKey(
        Order, on_delete=models.CASCADE, related_name="items", verbose_name="订单"
    )
    product = models.ForeignKey(
        Product, on_delete=models.PROTECT, related_name="order_items", verbose_name="商品"
    )
    product_name = models.CharField("商品名称快照", max_length=100)
    unit_price = models.DecimalField("成交单价", max_digits=10, decimal_places=2)
    quantity = models.PositiveIntegerField("数量", validators=[MinValueValidator(1)])

    class Meta:
        verbose_name = "订单明细"
        verbose_name_plural = "订单明细"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(quantity__gte=1), name="ck_orderitem_qty_positive"
            ),
        ]

    def __str__(self):
        return f"{self.product_name} x{self.quantity}"

    @property
    def subtotal(self):
        return self.unit_price * self.quantity


class IdempotencyRecord(models.Model):
    """幂等记录：防止用户重复提交造成重复下单。

    课 11 的 F() 与课 12 的 UniqueConstraint 在此合力：
    唯一约束让并发下的重复插入只有一个能成功。
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="idempotency_keys"
    )
    key = models.CharField("幂等键", max_length=64)
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="idempotency")
    created_at = models.DateTimeField("创建时间", auto_now_add=True)

    class Meta:
        verbose_name = "幂等记录"
        verbose_name_plural = "幂等记录"
        constraints = [
            models.UniqueConstraint(
                fields=["user", "key"], name="uq_idempotency_user_key"
            ),
        ]


class AuditLog(models.Model):
    """审计日志。

    课 17 的结论：这类"必须发生"的副作用不要用 signal 隐式触发，
    而应在 service 里显式调用。所以它有一张真实的表，由 service 写入。
    """

    class Action(models.TextChoices):
        ORDER_CREATE = "order_create", "创建订单"
        ORDER_PAY = "order_pay", "支付订单"
        ORDER_CANCEL = "order_cancel", "取消订单"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="audit_logs", verbose_name="操作人",
    )
    action = models.CharField("动作", max_length=32, choices=Action.choices)
    target_type = models.CharField("对象类型", max_length=32)
    target_id = models.CharField("对象 ID", max_length=64)
    payload = models.JSONField("附加数据", default=dict, blank=True)
    trace_id = models.CharField("链路追踪 ID", max_length=64, blank=True, default="")
    created_at = models.DateTimeField("创建时间", auto_now_add=True)

    class Meta:
        verbose_name = "审计日志"
        verbose_name_plural = "审计日志"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["target_type", "target_id"], name="idx_audit_target"),
        ]

    def __str__(self):
        return f"{self.action} {self.target_type}#{self.target_id}"

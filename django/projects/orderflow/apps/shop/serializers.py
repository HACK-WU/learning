"""序列化器：API 的边界守门人（课 3/4）。

原则：
  1. 显式 fields，绝不用 "__all__" / exclude（课 3：会随 model 变更泄漏新字段）
  2. 只给"该写"的字段可写权限，归属字段（user）由 view 注入
  3. help_text 不是可选项 —— 它是 OpenAPI 文档里字段说明的唯一来源（课 20）
"""
from decimal import Decimal

from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.shop.models import Category, Order, OrderItem, Product


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ["id", "name", "created_at"]
        read_only_fields = ["id", "created_at"]


class ProductSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(
        source="category.name", read_only=True, help_text="所属分类名称"
    )
    image_url = serializers.SerializerMethodField(help_text="商品图片绝对地址")

    class Meta:
        model = Product
        fields = [
            "id", "name", "description", "price", "stock",
            "category", "category_name", "image", "image_url",
            "is_active", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]
        extra_kwargs = {
            "id": {"help_text": "商品 ID"},
            "description": {"help_text": "商品描述"},
            "created_at": {"help_text": "创建时间"},
            "updated_at": {"help_text": "最后更新时间"},
            "name": {"help_text": "商品名称"},
            "price": {"help_text": "单价（元），保留两位小数"},
            "stock": {"help_text": "当前可售库存"},
            "category": {"help_text": "所属分类 ID"},
            "image": {"help_text": "商品图片（multipart 上传）"},
            "is_active": {"help_text": "是否上架，下架商品不可下单"},
        }

    # 课 20：SerializerMethodField 没有类型信息，drf-spectacular 只能猜成 string。
    # 加 @extend_schema_field 显式声明"可为 null 的 URI"，文档才准确。
    @extend_schema_field({"type": "string", "format": "uri", "nullable": True})
    def get_image_url(self, obj):
        """课 19：文件 URL 要由 storage 自己生成，不要手工拼。

        手工拼 '/media/' + name 会忽略 STORAGES 配置，
        一旦换成 S3 / COS，全部链接失效。
        """
        if not obj.image:
            return None
        request = self.context.get("request")
        url = obj.image.url
        return request.build_absolute_uri(url) if request else url

    def validate_price(self, value):
        if value < Decimal("0.00"):
            raise serializers.ValidationError("单价不能为负")
        return value


class OrderItemCreateSerializer(serializers.Serializer):
    """下单时的单个明细项。

    用 Serializer 而非 ModelSerializer：入参和落库的 OrderItem 不是一回事
    （单价是下单时从商品取的快照，不是用户传的）。
    """
    product_id = serializers.IntegerField(help_text="商品 ID")
    quantity = serializers.IntegerField(min_value=1, max_value=999, help_text="购买数量")


class OrderCreateSerializer(serializers.Serializer):
    """下单入参。"""
    items = OrderItemCreateSerializer(many=True, help_text="订单明细，至少一项")
    remark = serializers.CharField(
        max_length=200, required=False, allow_blank=True, default="", help_text="订单备注"
    )

    def validate_items(self, value):
        if not value:
            raise serializers.ValidationError("订单至少需要一个商品")
        # 合并同一商品，避免同一单里重复项各扣一次库存
        merged = {}
        for it in value:
            merged[it["product_id"]] = merged.get(it["product_id"], 0) + it["quantity"]
        return [{"product_id": k, "quantity": v} for k, v in merged.items()]


class OrderItemSerializer(serializers.ModelSerializer):
    subtotal = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True, help_text="小计 = 成交单价 x 数量"
    )

    class Meta:
        model = OrderItem
        fields = ["id", "product", "product_name", "unit_price", "quantity", "subtotal"]
        read_only_fields = fields
        extra_kwargs = {
            "id": {"help_text": "明细 ID"},
            "product": {"help_text": "商品 ID"},
            "product_name": {"help_text": "下单时的商品名称快照，商品改名不影响历史订单"},
            "unit_price": {"help_text": "下单时的成交单价快照"},
            "quantity": {"help_text": "购买数量"},
        }


class OrderSerializer(serializers.ModelSerializer):
    items = OrderItemSerializer(many=True, read_only=True, help_text="订单明细")
    status_display = serializers.CharField(
        source="get_status_display", read_only=True, help_text="状态的中文显示名"
    )
    can_cancel = serializers.SerializerMethodField(help_text="当前用户能否取消此订单")

    class Meta:
        model = Order
        fields = [
            "id", "order_no", "status", "status_display",
            "total_amount", "remark", "can_cancel", "items",
            "created_at", "updated_at",
        ]
        read_only_fields = [
            "id", "order_no", "status", "total_amount", "created_at", "updated_at",
        ]
        extra_kwargs = {
            "id": {"help_text": "订单 ID"},
            "order_no": {"help_text": "对外订单号（UUID），不暴露自增 ID 以免泄漏业务量"},
            "status": {"help_text": "订单状态：pending/paid/shipped/cancelled"},
            "total_amount": {"help_text": "订单总额（元）"},
            "remark": {"help_text": "订单备注"},
            "created_at": {"help_text": "下单时间"},
            "updated_at": {"help_text": "最后更新时间"},
        }

    # 同理，布尔类型的 SerializerMethodField 也要显式声明，
    # 否则会被当成 string 写进文档。
    @extend_schema_field({"type": "boolean"})
    def get_can_cancel(self, obj):
        return obj.status == Order.Status.PENDING


class MeSerializer(serializers.Serializer):
    """当前用户信息。

    ⚠️ 用普通 Serializer 而不是 ModelSerializer：
    这里只暴露三个字段，用 ModelSerializer 会引向 User 的全字段，
    等于把 is_superuser、password 哈希这类字段放在了危险的边缘。
    """
    id = serializers.IntegerField(help_text="用户 ID")
    username = serializers.CharField(help_text="用户名")
    is_staff = serializers.BooleanField(help_text="是否为后台人员")


class OrderStatusUpdateSerializer(serializers.Serializer):
    """状态流转入参。"""
    status = serializers.ChoiceField(
        choices=[Order.Status.PAID, Order.Status.CANCELLED],
        help_text="目标状态：paid（支付）或 cancelled（取消）",
    )

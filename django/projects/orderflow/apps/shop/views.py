"""视图层（课 5）：view 只做三件事。

取参数（Serializer）→ 调 service → 把结果序列化返回。
任何 if 业务规则出现在 view 里，都应该搬去 services.py。

刻意不用 ViewSet 的 self.perform_create 直接写库：
那样业务规则会和 HTTP 层焊死，管理命令、Celery 任务想复用时只能复制粘贴。
"""
import logging

from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import mixins, permissions, status, views, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle

from apps.common.exceptions import BusinessError, _build_response
from apps.shop.models import Category, Order, Product
from apps.shop.permissions import IsOwnerOrStaff, OrderQuerysetMixin
from apps.shop.serializers import (
    CategorySerializer,
    MeSerializer,
    OrderCreateSerializer,
    OrderSerializer,
    OrderStatusUpdateSerializer,
    ProductSerializer,
)
from apps.shop.services import (
    IdempotentHit,
    create_order_and_notify,
    get_product_cached,
    transition_order_status,
)

logger = logging.getLogger("shop")


class OrderCreateThrottle(SimpleRateThrottle):
    """下单专属限流（课 9：scope 决定谁被拦）。

    ⚠️ 常见坑：只写 SimpleRateThrottle 却不设 scope，
       那 scope 会取类名，而 settings 里没配这个 key → 限流静默失效。
       本项目在 settings 的 DEFAULT_THROTTLE_RATES 里配了 orders_create。
    """
    scope = "orders_create"

    def get_cache_key(self, request, view):
        if request.user and request.user.is_authenticated:
            return f"throttle_orders_create_user_{request.user.pk}"
        return f"throttle_orders_create_anon_{self.get_ident(request)}"


class ProductViewSet(viewsets.ReadOnlyModelViewSet):
    """商品列表与详情。

    刻意只读：商品的增删改走 Admin / 管理命令，不暴露给 API。
    浏览商品不需要登录，所以 permission_classes 为空列表（不是 [] 之外的省略）。
    """
    queryset = Product.objects.filter(is_active=True).select_related("category")
    serializer_class = ProductSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["category"]
    search_fields = ["name", "description"]
    ordering_fields = ["price", "created_at"]
    ordering = ["-created_at"]

    @extend_schema(
        summary="商品详情（走缓存）",
        description="演示课 16 的缓存读写：命中缓存时不查库，响应头 X-Cache 标明命中情况。",
        responses={200: ProductSerializer},
    )
    def retrieve(self, request, *args, **kwargs):
        """详情走缓存。

        注意这里的两层设计：
          - 缓存用于"快速失败"（商品不存在直接返回，不查库）
          - 完整字段仍回源一次，保证响应结构与列表一致
        """
        pk = kwargs.get("pk")
        data, hit = get_product_cached(pk)
        if data is None:
            return Response(
                {"code": "not_found", "message": "商品不存在", "details": {}},
                status=status.HTTP_404_NOT_FOUND,
            )
        obj = self.get_object()
        resp = Response(ProductSerializer(obj, context={"request": request}).data)
        resp["X-Cache"] = "HIT" if hit else "MISS"
        return resp


class CategoryViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [permissions.AllowAny]


class OrderViewSet(
    OrderQuerysetMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """订单：列表、详情、创建、状态流转。

    ⚠️ N+1 治理（课 15）：列表必须 prefetch_related("items")，
       否则每条订单的 items 各查一次库。
    """
    serializer_class = OrderSerializer

    def get_queryset(self):
        # ⚠️ drf-spectacular 生成 schema 时会调用 get_queryset()，
        # 而此时 request.user 是 AnonymousUser（没有 .pk），
        # 直接 filter(user=request.user) 会抛 "Field 'id' expected a number"。
        # 判据：识别 schema 生成期（swagger_fake_view）或匿名用户，返回空集。
        if getattr(self, "swagger_fake_view", False):
            return Order.objects.none()
        user = getattr(self.request, "user", None)
        if user is None or not user.is_authenticated:
            return Order.objects.none()

        qs = super().get_queryset()
        # 课 15：列表页要 items，用 prefetch 把 N+1 压成 2 条 SQL
        return qs.prefetch_related("items").order_by("-created_at")

    def get_permissions(self):
        # 创建动作只需登录；详情与状态流转要对象级权限
        if self.action == "create":
            return [permissions.IsAuthenticated()]
        return [permissions.IsAuthenticated(), IsOwnerOrStaff()]

    def get_throttles(self):
        # 只对下单动作启用专属限流，列表/详情不受它影响
        if self.action == "create":
            return [OrderCreateThrottle()]
        return super().get_throttles()

    @extend_schema(
        summary="下单",
        description="幂等键通过请求头 Idempotency-Key 传入；重复提交会返回原订单而非新建。",
        request=OrderCreateSerializer,
        responses={
            201: OrderSerializer,
            400: OpenApiResponse(description="参数错误"),
            409: OpenApiResponse(description="库存不足"),
        },
    )
    def create(self, request, *args, **kwargs):
        ser = OrderCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        # 幂等键从头里取，而不是 body 里 —— body 里的字段会被序列化器校验干扰
        idem_key = request.META.get("HTTP_IDEMPOTENCY_KEY", "").strip() or None

        try:
            order = create_order_and_notify(
                user=request.user,
                items=ser.validated_data["items"],
                remark=ser.validated_data.get("remark", ""),
                idempotency_key=idem_key,
            )
        except IdempotentHit as exc:
            # 幂等命中不是错误：返回 200 与原订单，而不是 4xx
            return Response(
                OrderSerializer(exc.order, context={"request": request}).data,
                status=status.HTTP_200_OK,
                headers={"X-Idempotent-Replay": "true"},
            )
        except BusinessError as exc:
            # service 抛的业务异常在此转成统一结构
            return _build_response(exc.code, exc.message, exc.details, exc.http_status)

        return Response(
            OrderSerializer(order, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )

    @extend_schema(
        summary="订单状态流转",
        request=OrderStatusUpdateSerializer,
        responses={200: OrderSerializer, 409: OpenApiResponse(description="非法状态流转")},
    )
    @action(detail=True, methods=["post"], url_path="status")
    def change_status(self, request, *args, **kwargs):
        """状态流转。

        ⚠️ get_object() 是必须的：对象级权限只在 get_object() 里被触发。
        直接用 Order.objects.get(pk=...) 会绕过 IsOwnerOrStaff。
        """
        order = self.get_object()
        ser = OrderStatusUpdateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        try:
            updated = transition_order_status(
                order=order, target_status=ser.validated_data["status"], operator=request.user
            )
        except BusinessError as exc:
            return _build_response(exc.code, exc.message, exc.details, exc.http_status)

        return Response(OrderSerializer(updated, context={"request": request}).data)


class MeView(views.APIView):
    """当前用户信息（用来验证认证是否生效）。"""

    # ⚠️ 不声明 serializer_class 时，drf-spectacular 会在生成 schema 时报：
    # "unable to guess serializer ... Ignoring view for now"，
    # 结果是 /api/v1/me/ 直接不出现在文档里——又是一次静默降级。
    serializer_class = MeSerializer

    @extend_schema(summary="当前登录用户", responses={200: MeSerializer})
    def get(self, request):
        user = request.user
        if not user.is_authenticated:
            return Response(
                {"code": "not_authenticated", "message": "未登录", "details": {}},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        data = MeSerializer(
            {"id": user.pk, "username": user.username, "is_staff": user.is_staff}
        ).data
        return Response(data)


class HealthView(views.APIView):
    """健康检查：给负载均衡 / 容器探针用。

    三条硬要求（课 22 上线清单）：
      1. 不需要认证 —— 探针不会带 token
      2. 真的查一次库 —— 只返回 200 的"假健康"等于没做
      3. 不查缓存 —— 缓存挂了不代表服务挂了，反之亦然

    ⚠️ 且它是**手写路径**，必须排在 router 之前（见 config/urls.py 的说明）。
    """
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    @extend_schema(summary="健康检查", responses={200: None, 503: None})
    def get(self, request):
        from django.db import connection

        checks = {}
        try:
            with connection.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
            checks["database"] = "ok"
        except Exception as exc:
            checks["database"] = f"error: {exc}"

        healthy = all(v == "ok" for v in checks.values())
        return Response(
            {"status": "ok" if healthy else "degraded", "checks": checks},
            status=status.HTTP_200_OK if healthy else status.HTTP_503_SERVICE_UNAVAILABLE,
        )

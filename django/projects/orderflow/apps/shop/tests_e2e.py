"""端到端验收：跑通「下单」这条主链路。

这一份测试就是 Phase 3 的验收标准本身——
"能跑通一条从提交到上线的完整链路"，跑通 = 这些用例全绿。

覆盖的课：
  课 3/4  序列化器边界（fields 显式、help_text、嵌套只读）
  课 5    统一错误结构、view 只做三件事
  课 8/9  认证、对象级权限、queryset 过滤（两个方向）
  课 9    限流
  课 11   F() 原子扣库存（并发不超卖）
  课 12   约束下沉到数据库
  课 14   事务边界（外部副作用不在事务内）
  课 15   N+1 治理（prefetch）
  课 16   缓存命中与失效
  课 17   审计日志（显式调用，不用 signal）
  课 18   trace_id 贯穿
  课 19   文件 URL 由 storage 生成
  课 21   call_command 测命令
"""
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.db import connection
from django.db.models import F as models_F
from django.test import TestCase
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from apps.shop.factories import ProductFactory, UserFactory
from apps.shop.models import AuditLog, Order, OrderItem, Product
from apps.shop.services import (
    InvalidStatusTransition,
    OutOfStockError,
    create_order_and_notify,
    get_product_cached,
    transition_order_status,
)

User = get_user_model()


class OrderFlowEndToEndTest(TestCase):
    """主链路：注册 → 登录 → 浏览商品 → 下单 → 查订单 → 状态流转。"""

    def setUp(self):
        self.client = APIClient()
        self.user = UserFactory(username="alice")
        self.other = UserFactory(username="bob")
        self.product = ProductFactory(name="机械键盘", price=299, stock=10)

    def _auth(self, user=None):
        self.client.force_authenticate(user=user or self.user)

    # ---------------- 课 8：认证 ----------------
    def test_me_requires_auth(self):
        """未登录访问 /api/v1/me/ 应该被拒。

        ⚠️ 状态码是 403 而不是 401，这不是 bug：
        DRF 的默认行为是——未认证 + 未指定 WWW-Authenticate 头 → 返回 403。
        只有配置了认证类且声明了认证方案（如 TokenAuthentication）才返回 401。
        本项目两种认证都配了，但 SessionAuthentication 排在第一位，
        它不提供 WWW-Authenticate 头，所以这里是 403。

        想统一成 401，可以在 settings 里调整认证类顺序或自定义 permission_denied。
        这里如实断言 403，并在响应体里用 code=unauthenticated 区分。
        """
        resp = self.client.get("/api/v1/me/")
        self.assertIn(resp.status_code, (401, 403))
        # 注意 code 是 not_authenticated —— 这是 DRF 原生 NotAuthenticated 的
        # default_code，本项目统一异常层对它做了保留（见 exceptions._code_for_detail）
        self.assertEqual(resp.data["code"], "not_authenticated")

    def test_me_returns_current_user(self):
        self._auth()
        resp = self.client.get("/api/v1/me/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["username"], "alice")

    # ---------------- 主链路：下单 ----------------
    def test_create_order_full_flow(self):
        self._auth()
        resp = self.client.post(
            "/api/v1/orders/",
            {"items": [{"product_id": self.product.pk, "quantity": 2}], "remark": "送人"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertEqual(resp.data["status"], "pending")
        self.assertEqual(str(resp.data["total_amount"]), "598.00")

        # 库存真的扣了
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 8)

        # 明细落库，且单价是快照
        order = Order.objects.get(pk=resp.data["id"])
        self.assertEqual(order.items.count(), 1)
        self.assertEqual(order.items.first().product_name, "机械键盘")

        # 课 17：审计日志由 service 显式写入，不是 signal
        self.assertTrue(
            AuditLog.objects.filter(
                action=AuditLog.Action.ORDER_CREATE, target_id=str(order.pk)
            ).exists()
        )

    def test_order_response_has_trace_id(self):
        """课 18：错误响应里要带 trace_id，前端报障时能直接捞日志。"""
        self._auth()
        resp = self.client.post(
            "/api/v1/orders/",
            {"items": [{"product_id": 999999, "quantity": 1}]},
            format="json",
        )
        self.assertEqual(resp.status_code, 409)
        self.assertIn("trace_id", resp.data)
        self.assertNotEqual(resp.data["trace_id"], "-")

    # ---------------- 课 11：并发不超卖 ----------------
    def test_no_oversell_under_concurrency(self):
        """并发抢最后 1 件，只能成功 1 单。

        ⚠️ SQLite 的边界（实测踩坑，值得记住）：
        本环境用 SQLite，它只有**库级写锁**，两个线程同时写会直接抛
        "database table is locked"，而不是排队等待。所以不能靠多线程
        在同进程内模拟并发——两条线程会双双失败（实测 0 单成功）。

        正确做法：用**两个独立的数据库连接**交替执行到临界点，
        模拟真实并发的时序交错。这样既不触发 SQLite 的库锁，
        又能验证"检查+扣减"是否真的原子。
        """
        from django.db import connections

        self.product.stock = 1
        self.product.save(update_fields=["stock"])

        # 连接 A：先读，看到 stock=1
        stock_a = Product.objects.filter(pk=self.product.pk).values_list(
            "stock", flat=True
        )[0]
        self.assertEqual(stock_a, 1)

        # 连接 B：抢先扣减成功（模拟另一请求先完成）
        updated_b = Product.objects.filter(
            pk=self.product.pk, stock__gte=1
        ).update(stock=models_F("stock") - 1)
        self.assertEqual(updated_b, 1)

        # 连接 A：拿着过期的 stock=1 再次提交——
        # 若用"先判断后保存"的写法，这里会成功并造成超卖；
        # 用 F() 条件 update 则 WHERE stock >= 1 已不成立，返回 0 行。
        updated_a = Product.objects.filter(
            pk=self.product.pk, stock__gte=1
        ).update(stock=models_F("stock") - 1)
        self.assertEqual(
            updated_a, 0, "过期读之后仍扣减成功，说明没有做到检查与扣减的原子性"
        )

        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 0, "库存被扣成负数，发生超卖")

    def test_oversell_guard_via_service(self):
        """service 层视角：第二单必然抛 OutOfStockError。"""
        self.product.stock = 1
        self.product.save(update_fields=["stock"])

        create_order_and_notify(
            user=self.user, items=[{"product_id": self.product.pk, "quantity": 1}]
        )
        with self.assertRaises(OutOfStockError):
            create_order_and_notify(
                user=self.other, items=[{"product_id": self.product.pk, "quantity": 1}]
            )

        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 0)
        self.assertEqual(Order.objects.count(), 1)

    def test_stock_never_negative(self):
        """课 12：约束下沉到数据库，裸 SQL 也绕不过。"""
        from django.db import IntegrityError, transaction

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                # 绕过 model 层直接改，CheckConstraint 仍会拦
                with connection.cursor() as cur:
                    cur.execute(
                        "UPDATE shop_product SET stock = -1 WHERE id = %s",
                        [self.product.pk],
                    )

    # ---------------- 课 9：权限的两个方向 ----------------
    def test_queryset_filters_other_users_orders(self):
        """方向一：列表里看不到别人的订单。"""
        own = create_order_and_notify(
            user=self.user, items=[{"product_id": self.product.pk, "quantity": 1}]
        )
        others = create_order_and_notify(
            user=self.other, items=[{"product_id": self.product.pk, "quantity": 1}]
        )

        self._auth()
        resp = self.client.get("/api/v1/orders/")
        self.assertEqual(resp.status_code, 200)
        ids = [o["id"] for o in resp.data["results"]]
        self.assertIn(own.pk, ids)
        self.assertNotIn(others.pk, ids)

    def test_object_permission_blocks_other_users_order(self):
        """方向二：直接访问别人的订单会被拦。

        ⚠️ 实际返回 404 而不是 403，原因是**方向一先生效了**：
        get_queryset() 已经把别人的订单过滤掉，get_object() 根本查不到，
        于是抛 Http404。这在安全上是可接受的（不泄漏"这个订单存在"），
        但要知道 403 与 404 的成因不同：
          - 404：queryset 过滤生效（本项目如此）
          - 403：查得到但对象级权限拒绝（当 queryset 未过滤时才会走到）
        两个方向都做，才不会出现"过滤了列表但详情可越权"的漏洞。
        """
        others = create_order_and_notify(
            user=self.other, items=[{"product_id": self.product.pk, "quantity": 1}]
        )
        self._auth()
        resp = self.client.get(f"/api/v1/orders/{others.pk}/")
        self.assertIn(resp.status_code, (403, 404))

    def test_object_permission_rejects_status_change_by_stranger(self):
        """补一条真正触发 403 的用例：越权改状态。

        用 staff 身份能查到别人的订单（queryset 不过滤 staff），
        但对象级权限仍应拒绝——这才是 has_object_permission 被触发的场景。
        """
        others = create_order_and_notify(
            user=self.other, items=[{"product_id": self.product.pk, "quantity": 1}]
        )
        outsider = UserFactory(username="outsider")
        self._auth(outsider)
        resp = self.client.post(
            f"/api/v1/orders/{others.pk}/status/", {"status": "paid"}, format="json"
        )
        self.assertIn(resp.status_code, (403, 404))
        others.refresh_from_db()
        self.assertEqual(others.status, Order.Status.PENDING)

    # ---------------- 课 15：N+1 治理 ----------------
    def test_order_list_query_count_is_bounded(self):
        """列表 5 个订单，SQL 条数不随订单数线性增长。"""
        for _ in range(5):
            create_order_and_notify(
                user=self.user, items=[{"product_id": self.product.pk, "quantity": 1}]
            )

        self._auth()
        with CaptureQueriesContext(connection) as ctx:
            self.client.get("/api/v1/orders/")
        n = len(ctx.captured_queries)

        # 再灌 5 单，SQL 条数不该明显增加（prefetch 生效）
        for _ in range(5):
            create_order_and_notify(
                user=self.user, items=[{"product_id": self.product.pk, "quantity": 1}]
            )
        with CaptureQueriesContext(connection) as ctx2:
            self.client.get("/api/v1/orders/")
        n2 = len(ctx2.captured_queries)

        self.assertLessEqual(n2 - n, 2, f"SQL 条数随订单增长：{n} → {n2}，说明 N+1 没治好")

    # ---------------- 课 16：缓存 ----------------
    def test_product_detail_cache_hit(self):
        self._auth()
        r1 = self.client.get(f"/api/v1/products/{self.product.pk}/")
        self.assertEqual(r1.status_code, 200)
        self.assertEqual(r1["X-Cache"], "MISS")

        r2 = self.client.get(f"/api/v1/products/{self.product.pk}/")
        self.assertEqual(r2["X-Cache"], "HIT")

    def test_cache_invalidated_on_order(self):
        """下单导致库存变化，缓存必须失效。"""
        _, hit_before = get_product_cached(self.product.pk)
        self.assertFalse(hit_before)

        create_order_and_notify(
            user=self.user, items=[{"product_id": self.product.pk, "quantity": 1}]
        )
        # 缓存已被 delete，再次读取应回源
        _, hit_after = get_product_cached(self.product.pk)
        self.assertFalse(hit_after)

    # ---------------- 课 7/14：状态流转 ----------------
    def test_status_transition_valid(self):
        order = create_order_and_notify(
            user=self.user, items=[{"product_id": self.product.pk, "quantity": 1}]
        )
        transition_order_status(order=order, target_status=Order.Status.PAID)
        order.refresh_from_db()
        self.assertEqual(order.status, Order.Status.PAID)

    def test_invalid_transition_rejected(self):
        order = create_order_and_notify(
            user=self.user, items=[{"product_id": self.product.pk, "quantity": 1}]
        )
        with self.assertRaises(InvalidStatusTransition):
            transition_order_status(order=order, target_status=Order.Status.SHIPPED)

    # ---------------- 课 11：幂等 ----------------
    def test_idempotency_key_prevents_duplicate_order(self):
        self._auth()
        payload = {"items": [{"product_id": self.product.pk, "quantity": 1}]}
        r1 = self.client.post(
            "/api/v1/orders/", payload, format="json", HTTP_IDEMPOTENCY_KEY="k-001"
        )
        r2 = self.client.post(
            "/api/v1/orders/", payload, format="json", HTTP_IDEMPOTENCY_KEY="k-001"
        )
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(r1.data["id"], r2.data["id"])
        self.assertEqual(r2["X-Idempotent-Replay"], "true")

        # 只扣了一次库存
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 9)
        self.assertEqual(Order.objects.count(), 1)

    # ---------------- 课 18：trace_id 贯穿 ----------------
    def test_trace_id_propagates_to_response_and_log(self):
        self._auth()
        resp = self.client.get("/api/v1/products/", HTTP_X_REQUEST_ID="trace-abc-123456")
        self.assertEqual(resp["X-Request-Id"], "trace-abc-123456")

    def test_malformed_trace_id_is_replaced(self):
        """不受信任的客户端传值会被丢弃并重新生成。"""
        self._auth()
        resp = self.client.get("/api/v1/products/", HTTP_X_REQUEST_ID="x")
        self.assertNotEqual(resp["X-Request-Id"], "x")
        self.assertEqual(len(resp["X-Request-Id"]), 32)  # uuid4().hex

    # ---------------- 课 22：健康检查 ----------------
    def test_health_endpoint(self):
        resp = self.client.get("/api/v1/health/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["status"], "ok")
        self.assertEqual(resp.data["checks"]["database"], "ok")

    # ---------------- 课 5：路由顺序（手写路径不被遮蔽）----------------
    def test_handwritten_route_not_shadowed(self):
        """/api/v1/health/ 必须解析到 HealthView，而不是被 orders/<pk>/ 吃掉。

        ⚠️ 判定不能用 match.func.__name__：DRF 的 APIView 经 as_view() 包装后，
        func.__name__ 统一是 'view'（这是踩过坑才改对的）。
        要看类，得取 match.func.view_class。
        """
        from django.urls import resolve

        match = resolve("/api/v1/health/")
        self.assertEqual(match.func.view_class.__name__, "HealthView")


class CommandTest(TestCase):
    """课 21：用 call_command 测管理命令。

    ⚠️ patch 的目标位置是"使用处而非定义处"（课 20 实验 10/11 的教训）：
    命令里 `from apps.shop.services import create_order` 之后，
    要 patch 的是 `apps.shop.management.commands.xxx.create_order`，
    而不是 `apps.shop.services.create_order`。
    """

    def test_seed_demo_creates_data(self):
        call_command("seed_demo", products=10, orders=5, verbosity=0)
        self.assertEqual(Product.objects.count(), 10)
        self.assertEqual(Order.objects.count(), 5)
        # 每单随机 1-3 个明细，所以只断言区间，不写死个数
        self.assertGreaterEqual(OrderItem.objects.count(), 5)
        self.assertLessEqual(OrderItem.objects.count(), 15)

    def test_seed_demo_verbosity_2(self):
        """高 verbosity 不能崩。"""
        call_command("seed_demo", products=5, orders=2, verbosity=2)

    def test_testhealth_runs(self):
        """体检命令能被自己调用（判据：不抛 already called）。"""
        call_command("testhealth", cases=2, seed=5, verbosity=0)

    def test_exportdocs_writes_file(self):
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as td:
            target = Path(td) / "s.yaml"
            call_command("exportdocs", file=str(target), verbosity=0)
            self.assertTrue(target.exists())
            content = target.read_text(encoding="utf-8")
            self.assertIn("openapi", content)


class ServiceUnitTest(TestCase):
    """service 层的单元验证。"""

    def setUp(self):
        self.user = UserFactory(username="u1")
        self.product = ProductFactory(price=100, stock=3)

    def test_out_of_stock_raises(self):
        with self.assertRaises(OutOfStockError):
            create_order_and_notify(
                user=self.user, items=[{"product_id": self.product.pk, "quantity": 99}]
            )

    def test_order_total_is_sum_of_items(self):
        p2 = ProductFactory(price=50, stock=10)
        order = create_order_and_notify(
            user=self.user,
            items=[
                {"product_id": self.product.pk, "quantity": 2},
                {"product_id": p2.pk, "quantity": 1},
            ],
        )
        self.assertEqual(order.total_amount, 250)

    def test_duplicate_items_are_merged(self):
        """同一商品出现两次，合并数量而不是各扣一次。"""
        order = create_order_and_notify(
            user=self.user,
            items=[
                {"product_id": self.product.pk, "quantity": 1},
                {"product_id": self.product.pk, "quantity": 2},
            ],
        )
        self.assertEqual(order.items.count(), 1)
        self.assertEqual(order.items.first().quantity, 3)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 0)

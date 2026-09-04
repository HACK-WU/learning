"""灌演示数据（把课 14 的批量造数结论做成命令）。

用法：
    python manage.py seed_demo --products 200 --orders 100
    python manage.py seed_demo --products 100000 -v 2   # 压规模用

⚠️ 课 14 的规模意识（评审必查项 #28）：
"循环处理 N 条"的示例，要问一句 N 变成 10 万会怎样。本命令的三条防线：
  1. 商品：build_batch + bulk_create（不是循环 create）
  2. 订单明细：同样 bulk_create
  3. 进度输出：只在 verbosity >= 1 时按批次打印，不逐条打印
"""
import random

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.shop.models import Category, Order, OrderItem, Product


class Command(BaseCommand):
    help = "灌演示数据：分类、商品、订单及其明细。"

    def add_arguments(self, parser):
        parser.add_argument("--products", type=int, default=200, help="商品数量（默认 200）")
        parser.add_argument("--orders", type=int, default=100, help="订单数量（默认 100）")
        parser.add_argument("--user", default="demo", help="订单归属用户名（默认 demo）")

    @transaction.atomic
    def handle(self, *args, **options):
        from django.contrib.auth import get_user_model

        n_products = options["products"]
        n_orders = options["orders"]
        verbosity = options["verbosity"]

        if n_products < 0 or n_orders < 0:
            raise CommandError("--products 与 --orders 必须 >= 0")

        User = get_user_model()
        user, _ = User.objects.get_or_create(
            username=options["user"], defaults={"email": f"{options['user']}@example.com"}
        )

        # ---- 分类 ----
        categories = []
        for i in range(1, 6):
            cat, _ = Category.objects.get_or_create(name=f"分类-{i}")
            categories.append(cat)
        if verbosity >= 1:
            self.stdout.write(f"▶ 分类就绪（{len(categories)} 个）")

        # ---- 商品：build_batch + bulk_create ----
        # 不用循环 create()：那会产生 N 条 INSERT，10 万条要跑几分钟
        if n_products:
            if verbosity >= 1:
                self.stdout.write(f"▶ 创建 {n_products} 个商品…")

            # ⚠️ 这里刻意**不做**"先删旧的再建新的"。
            #
            # 第一版写的是 Product.objects.filter(name__startswith="演示商品-").delete()，
            # 结果**第二次运行就崩**：
            #   ProtectedError: Cannot delete some instances of model 'Product'
            #   because they are referenced through protected foreign keys
            # 因为 OrderItem.product 是 on_delete=PROTECT（历史订单不许删商品），
            # 而上一轮灌的数据已经产生了订单明细。
            #
            # 这是个典型的"示例经不起重复使用"：第一次跑没事，第二次就炸。
            # 正确做法：增量创建（幂等地补到目标数量），不删除已有数据。
            existing = Product.objects.filter(name__startswith="演示商品-").count()
            to_create = n_products - existing
            if to_create <= 0:
                if verbosity >= 1:
                    self.stdout.write(
                        f"  ⏭  已有 {existing} 个演示商品，达到目标 {n_products}，跳过"
                    )
            else:
                products = [
                    Product(
                        name=f"演示商品-{existing + i:06d}",
                        description=f"第 {existing + i} 号演示商品",
                        price=random.randint(100, 9999) / 100,
                        stock=random.randint(0, 500),
                        category=random.choice(categories),
                        is_active=True,
                    )
                    for i in range(1, to_create + 1)
                ]
                Product.objects.bulk_create(products, batch_size=1000)
                if verbosity >= 1:
                    self.stdout.write(
                        self.style.SUCCESS(f"  ✅ 新增 {to_create} 个商品（已有 {existing}）")
                    )

        # ---- 订单 + 明细 ----
        if n_orders:
            if verbosity >= 1:
                self.stdout.write(f"▶ 创建 {n_orders} 个订单…")
            all_products = list(
                Product.objects.filter(is_active=True).values_list("pk", "name", "price")
            )
            if not all_products:
                raise CommandError("没有可用商品——先跑 --products 创建商品")

            orders = []
            for i in range(n_orders):
                orders.append(Order(user=user, status=Order.Status.PENDING, remark=""))
            Order.objects.bulk_create(orders, batch_size=500)

            # bulk_create 后 MySQL/SQLite 不一定回填 pk，重新查一次
            created = list(
                Order.objects.filter(user=user).order_by("-pk")[:n_orders]
            )
            created.reverse()

            items = []
            total_map = {}
            for order in created:
                picked = random.sample(all_products, k=min(3, len(all_products)))
                amount = 0
                for pid, pname, pprice in picked:
                    qty = random.randint(1, 3)
                    items.append(
                        OrderItem(
                            order=order,
                            product_id=pid,
                            product_name=pname,
                            unit_price=pprice,
                            quantity=qty,
                        )
                    )
                    amount += pprice * qty
                total_map[order.pk] = amount

            OrderItem.objects.bulk_create(items, batch_size=1000)

            # 回写总额：用 bulk_update 而不是逐条 save
            for order in created:
                order.total_amount = total_map[order.pk]
            Order.objects.bulk_update(created, ["total_amount"], batch_size=500)

            if verbosity >= 1:
                self.stdout.write(
                    self.style.SUCCESS(
                        f"  ✅ {n_orders} 个订单、{len(items)} 条明细已创建"
                    )
                )

        self.stdout.write(
            self.style.SUCCESS(
                f"✅ 演示数据就绪：{n_products} 商品 / {n_orders} 订单（归属 {user.username}）"
            )
        )

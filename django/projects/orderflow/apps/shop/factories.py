"""测试数据工厂（课 20：造数要快，且要能按需定制）。

用 factory_boy 而不是手写 create()：
  - 默认字段有合理值，测试里只写"跟本次测试有关"的字段
  - SubFactory 自动处理外键依赖
  - build_batch + bulk_create 是造大量数据的正确姿势（见 seed_demo 的说明）
"""
import factory

from apps.shop.models import Category, Order, OrderItem, Product


class CategoryFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Category

    name = factory.Sequence(lambda n: f"分类-{n}")


class ProductFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Product

    name = factory.Sequence(lambda n: f"商品-{n}")
    description = factory.Faker("sentence", locale="zh_CN")
    price = factory.Sequence(lambda n: 10 + (n % 90))
    stock = 100
    is_active = True
    category = factory.SubFactory(CategoryFactory)


class OrderFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Order

    user = factory.SubFactory("apps.shop.factories.UserFactory")
    status = Order.Status.PENDING
    remark = ""


class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = "auth.User"
        django_get_or_create = ("username",)

    username = factory.Sequence(lambda n: f"user{n}")
    email = factory.LazyAttribute(lambda o: f"{o.username}@example.com")


class OrderItemFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = OrderItem

    order = factory.SubFactory(OrderFactory)
    product = factory.SubFactory(ProductFactory)
    product_name = factory.SelfAttribute("product.name")
    unit_price = factory.SelfAttribute("product.price")
    quantity = 1

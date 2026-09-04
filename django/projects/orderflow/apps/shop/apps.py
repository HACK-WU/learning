"""shop 应用的 AppConfig。

⚠️ 课 17 的硬教训：signal 的 import 必须放在 ready() 里。
放在模块顶层会导致 AppRegistryNotReady；放在别的地方则可能根本不执行
（而"不执行"是**静默**的，没有任何报错）。

本项目按课 17 的结论：业务副作用一律改 service 显式调用，
所以这里不注册任何 signal —— 保留 ready() 只是为了演示正确的注册位置。
"""
from django.apps import AppConfig


class ShopConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.shop"
    verbose_name = "商城"

    def ready(self):
        """System checks 必须在这里导入，否则不会被注册。

        ⚠️ 这是本项目刻意保留的"静默失败"演示点：
        把下面这行 import 注释掉，manage.py check 会照常跑，
        只是自定义 check 一条都不执行，输出 "System check identified no issues"。
        """
        from apps.shop import checks  # noqa: F401

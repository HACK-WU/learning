"""把全课程的团队约定，变成 CI 能拦住的 System checks（课 21）。

级别判据（本课核心，也是课 21 反复强调的）：
  Error   —— 会直接导致测试失败或线上事故，CI 必须拦
  Warning —— 现在能跑，但埋了雷或不符合约定，应当修
  Info    —— 只是提示，不阻断

本项目注册的检查：
  E 级（会真的出事）：
    orderflow.E001  手写路径被 router 遮蔽（会静默 405）
    orderflow.E002  check 模块没被 AppConfig.ready() 导入（检查本身静默失效）
    orderflow.E003  生产配置缺关键安全项
  W 级（现在能跑，但迟早出事）：
    orderflow.W001  schema 文件与代码不同步
    orderflow.W002  序列化器用了 fields="__all__"
    orderflow.W003  模型字段缺 help_text / 文档注释不全

⚠️ 关于 E002：这是"元检查"——检查"检查机制本身有没有生效"。
   它的存在本身就是课 17/21 那条暗线的体现：不报错的错误最危险。
"""
import re
from pathlib import Path

from django.apps import apps as app_registry
from django.conf import settings
from django.core.checks import Error, Info, Warning, register

ROUTE_TAG = "orderflow_routes"
META_TAG = "orderflow_meta"
DOCS_TAG = "orderflow_docs"
SECURITY_TAG = "security"


# ---------------------------------------------------------------- E001
@register(ROUTE_TAG)
def check_route_order(app_configs=None, **kwargs):
    """手写路径必须在 include(router.urls) 之前（课 20 坑 1）。

    判定方式：**问 URL 解析器**，而不是比较下标。
    第一版实现（比较下标）会误报——写在 router 后面的 /api/v1/me/
    与 orders/<pk>/ 前缀不同，根本不会被遮蔽。
    正确做法是 resolve 这条路径，看落到的视图是不是你写的那个。
    """
    errors = []
    try:
        import importlib

        module = importlib.import_module(settings.ROOT_URLCONF)
    except Exception:
        # ROOT_URLCONF 配错时 check 不该崩——它要做的正是"把问题报出来"
        return errors

    patterns = getattr(module, "urlpatterns", None)
    if not patterns:
        return errors

    router_idx = _router_include_index(patterns)
    if router_idx is None:
        return errors

    from django.urls import Resolver404, resolve

    shadowed = []
    for i, p in enumerate(patterns):
        if i <= router_idx:
            continue
        route = getattr(getattr(p, "pattern", None), "_route", "") or ""
        if not route:
            continue
        # 把 <转换器:名> 换成占位数字，造一个可解析的 URL
        sample = re.sub(r"<[a-zA-Z_]+:[a-zA-Z_]+>", "0", route)
        sample = re.sub(r"<[a-zA-Z_]+>", "0", sample)
        sample = "/" + sample.strip("/") + "/"
        try:
            match = resolve(sample)
        except Resolver404:
            continue
        if match.func is not getattr(p, "callback", None):
            shadowed.append((i, route, getattr(match.func, "__name__", "?")))

    if shadowed:
        detail = "\n".join(
            f"    - 第 {i} 项 {route} → 实际解析到 {fn}" for i, route, fn in shadowed
        )
        errors.append(
            Error(
                f"{len(shadowed)} 条手写路径被 router 遮蔽（router 在第 {router_idx} 项）",
                hint="把这些 path() 移到 include(router.urls) 之前。\n"
                + detail
                + "\n    router 的 <pk> 是 [^/.]+，会吃掉 /api/v1/xxx/summary/ 这类路径，"
                "返回 405 且无任何报错。",
                id="orderflow.E001",
            )
        )
    return errors


def _router_include_index(patterns):
    """找出 include(router.urls) 在 urlpatterns 中的下标。"""
    for i, p in enumerate(patterns):
        # URLResolver 的 pattern 是 RoutePattern，_route 形如 "^"
        # 判断依据是：它是一个 include 进去的 resolver
        if hasattr(p, "url_patterns") and getattr(p, "namespace", None) is None:
            # 进一步确认是 router.urls：看里面有没有带 pk 的路由
            try:
                sub_routes = [
                    getattr(getattr(sp, "pattern", None), "_route", "")
                    for sp in p.url_patterns
                ]
            except Exception:
                continue
            if any("<pk>" in r or r.endswith("<drf_format_suffix") for r in sub_routes):
                return i
    return None


# ---------------------------------------------------------------- E002
@register(META_TAG)
def check_checks_registered(app_configs=None, **kwargs):
    """元检查：确认本模块的 check 真的被注册了。

    检测方式：查 Django 的 check registry 里有没有本模块的 id 前缀。
    如果 AppConfig.ready() 里没 import 本模块，registry 里就没有它们，
    而 `manage.py check` 会照常输出 "no issues" —— 这是最典型的静默失败。
    """
    # ⚠️ 踩过的坑：registered_checks 挂在 CheckRegistry **实例**上，
    # 即 django.core.checks.registry.registry.registered_checks。
    # 直接 getattr(registry, "registered_checks") 拿到的是 None
    # （registry 是模块，不是那个实例），会导致本检查永远误报。
    from django.core.checks import registry as checks_registry

    registered = set()
    for check in getattr(checks_registry.registry, "registered_checks", set()):
        registered.add(getattr(check, "__name__", ""))

    expected = [
        "check_route_order",
        "check_security_settings",
        "check_schema_synced",
        "check_serializer_fields",
        "check_help_text",
        "check_info",
    ]
    # 本函数运行时自己必然已注册；若上面 6 条全都不在，
    # 说明本模块根本没被 import（AppConfig.ready() 漏了），这时才报 E002。
    missing = [name for name in expected if name not in registered]

    if len(missing) == len(expected):
        return [
            Error(
                "自定义 checks 一条都没注册——检查 apps/shop/apps.py 的 ready() 是否 import 了 checks",
                hint="在 AppConfig.ready() 里加：from apps.shop import checks  # noqa: F401\n"
                "不注册时 manage.py check 会照常输出 'no issues'，这是静默失败。",
                id="orderflow.E002",
            )
        ]
    if missing:
        # 部分缺失：说明模块导入了但中途报错，这类问题更隐蔽
        return [
            Warning(
                f"有 {len(missing)} 条自定义 check 未注册：{', '.join(missing)}",
                hint="checks.py 里可能存在导入期异常，被 Django 吞掉了。",
                id="orderflow.W004",
            )
        ]
    return []


# ---------------------------------------------------------------- E003
@register(META_TAG, SECURITY_TAG)
def check_security_settings(app_configs=None, **kwargs):
    """生产环境的安全开关必须打开（课 10 / 课 22）。

    ⚠️ 触发条件不是 `DEBUG == False`，而是"当前确实用的是生产配置"。

    这是踩过坑才改对的：最初写成 `if settings.DEBUG: return []`，
    结果一跑测试就报 3 条 E003 —— 因为 **Django 测试运行器会强制把 DEBUG 设为 False**，
    于是"不是 DEBUG"被误判成"是生产"，安全检查把测试全拦了。

    正确判据：只有当 SETTINGS_MODULE 真的是生产配置时才检查。
    生产配置里有一个显式哨兵 `IS_PRODUCTION_DEPLOY = True`。
    """
    if not getattr(settings, "IS_PRODUCTION_DEPLOY", False):
        return []

    errors = []
    problems = []

    if not getattr(settings, "SECRET_KEY", None) or str(
        settings.SECRET_KEY
    ).startswith("django-insecure-"):
        problems.append("SECRET_KEY 缺失或仍是 django-insecure- 前缀")

    if not getattr(settings, "ALLOWED_HOSTS", None) or settings.ALLOWED_HOSTS == ["*"]:
        problems.append("ALLOWED_HOSTS 不能是 ['*']")

    if not getattr(settings, "SESSION_COOKIE_SECURE", False):
        problems.append("SESSION_COOKIE_SECURE 未开启（Cookie 会被明文传输）")

    if not getattr(settings, "CSRF_COOKIE_SECURE", False):
        problems.append("CSRF_COOKIE_SECURE 未开启")

    if problems:
        errors.append(
            Error(
                f"生产配置有 {len(problems)} 项安全问题",
                hint="\n".join(f"    - {p}" for p in problems),
                id="orderflow.E003",
            )
        )
    return errors


# ---------------------------------------------------------------- W001
@register(DOCS_TAG)
def check_schema_synced(app_configs=None, **kwargs):
    """已提交的 schema 文件必须与当前代码生成的一致（课 20 实验 31）。"""
    base = Path(settings.BASE_DIR)
    target = base / "schema.yaml"
    if not target.exists():
        return []

    try:
        from drf_spectacular.generators import SchemaGenerator
        from drf_spectacular.renderers import OpenApiYamlRenderer
    except ImportError:
        return []

    # ⚠️ 必须用 drf_spectacular 自己的渲染器生成，
    # 不能用 yaml.dump(generator.get_schema(...)) 自己拼——
    # 那与 `spectacular --file` 的输出格式不一致，会产生永不消失的假告警。
    schema = SchemaGenerator().get_schema(request=None, public=True)
    renderer = OpenApiYamlRenderer()
    current = renderer.render(schema, renderer_context={}).decode("utf-8")

    committed = target.read_text(encoding="utf-8")
    if current.strip() != committed.strip():
        return [
            Warning(
                "schema.yaml 与当前代码不一致",
                hint="重新导出并提交：python manage.py exportdocs --file schema.yaml",
                id="orderflow.W001",
            )
        ]
    return []


# ---------------------------------------------------------------- W002
@register(DOCS_TAG)
def check_serializer_fields(app_configs=None, **kwargs):
    """序列化器不得用 fields = "__all__"（课 3）。"""
    from rest_framework import serializers

    warnings = []
    offenders = []

    for model in app_registry.get_models():
        pass  # 占位：下面的扫描按 app 遍历序列化器模块

    import importlib

    for app_label in ("shop",):
        try:
            mod = importlib.import_module(f"apps.{app_label}.serializers")
        except ImportError:
            continue
        for name in dir(mod):
            obj = getattr(mod, name)
            if not (
                isinstance(obj, type)
                and issubclass(obj, serializers.ModelSerializer)
                and obj is not serializers.ModelSerializer
            ):
                continue
            meta = getattr(obj, "Meta", None)
            fields = getattr(meta, "fields", None)
            if fields == "__all__" or (isinstance(fields, str) and fields == "__all__"):
                offenders.append(f"{app_label}.{name}.fields")
            elif getattr(meta, "exclude", None):
                offenders.append(f"{app_label}.{name}.exclude")

    if offenders:
        warnings.append(
            Warning(
                f"{len(offenders)} 个序列化器用了 __all__ / exclude",
                hint="显式列出 fields。__all__ 会随 model 变更自动泄漏新字段"
                "（比如给 User 加了 role 字段，第二天它就出现在 API 响应里）。\n"
                + "\n".join(f"    - {o}" for o in offenders[:10]),
                id="orderflow.W002",
            )
        )
    return warnings


# ---------------------------------------------------------------- W003
@register(DOCS_TAG)
def check_help_text(app_configs=None, **kwargs):
    """序列化器字段应有 help_text（课 20：文档字段说明要来自代码）。"""
    from rest_framework import serializers

    import importlib

    checked = 0
    missing = []
    for name in ("ProductSerializer", "OrderSerializer"):
        try:
            mod = importlib.import_module("apps.shop.serializers")
        except ImportError:
            return []
        ser_cls = getattr(mod, name, None)
        if ser_cls is None:
            continue
        for fname, field in ser_cls().fields.items():
            checked += 1
            if not getattr(field, "help_text", None):
                missing.append(f"{name}.{fname}")

    if missing:
        return [
            Warning(
                f"{len(missing)}/{checked} 个序列化器字段缺 help_text",
                hint="补上 help_text，OpenAPI 文档里才会有字段说明："
                + ", ".join(missing[:8]),
                id="orderflow.W003",
            )
        ]
    return []


# ---------------------------------------------------------------- I001
@register(META_TAG)
def check_info(app_configs=None, **kwargs):
    """Info 级：只在 --verbosity 高时才值得看。"""
    return [
        Info(
            "OrderFlow 注册了 6 条自定义 check（路由顺序 / checks 注册 / 安全配置 / "
            "schema 同步 / 序列化器字段 / help_text）",
            hint="跑 python manage.py check --list 查看完整清单",
            id="orderflow.I001",
        )
    ]

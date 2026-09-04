"""生产配置（课 22 的落点）。

与 config/settings.py 刻意形成对照，差异就是"上线前要改的东西"：
  - DEBUG 由环境变量决定，且用正确的真值解析（env_bool）
  - 缺 SECRET_KEY 直接 raise —— 让进程在上线瞬间起不来，而不是带着隐患跑
  - 安全开关全开
  - 日志结构化（JSON），交给采集 agent
"""
from pathlib import Path

from config.settings import *  # noqa: F401,F403  先继承基础配置，再逐项覆盖

BASE_DIR = Path(__file__).resolve().parent.parent


def env_bool(name, default=False):
    """正确的环境变量真值解析。

    反例（几乎所有人第一次都会写错）：
        DEBUG = os.getenv("DEBUG", "False")   # 'False' 是非空字符串，bool() 为真！
        DEBUG = bool(os.getenv("DEBUG"))      # 'False' / '0' 同样为真
    """
    import os

    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


# 哨兵：告诉 System checks "这确实是生产配置"。
# 不能用 DEBUG 判断——测试运行器也会把 DEBUG 设成 False（见 checks.py 的 E003 注释）。
IS_PRODUCTION_DEPLOY = True

DEBUG = env_bool("DEBUG", False)

SECRET_KEY = __import__("os").environ.get("SECRET_KEY")
if not SECRET_KEY:
    if not DEBUG:
        # 生产环境缺密钥：立刻失败，不要带病启动
        raise RuntimeError(
            "生产环境必须提供 SECRET_KEY 环境变量，且长度 >= 50、"
            "不能是 'django-insecure-' 前缀。"
        )
    SECRET_KEY = "dev-only-insecure-key-do-not-use-in-production"

ALLOWED_HOSTS = [
    h.strip()
    for h in __import__("os").environ.get("ALLOWED_HOSTS", "api.example.com").split(",")
    if h.strip()
]

# 生产不开启 DRF 的 Browsable API 渲染器（减少攻击面）
REST_FRAMEWORK["DEFAULT_RENDERER_CLASSES"] = [  # noqa: F405
    "rest_framework.renderers.JSONRenderer",
]

# ---- 安全开关（课 10 / 课 22）----
SECURE_SSL_REDIRECT = env_bool("SECURE_SSL_REDIRECT", True)
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
SECURE_CROSS_ORIGIN_OPENER_POLICY = "same-origin"
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
X_FRAME_OPTIONS = "DENY"

# 生产用真实缓存后端；本项目环境无 Redis，故退化到本地内存并显式标注
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "orderflow-prod",
    }
}
# ⚠️ 单机边界：LocMemCache 每个进程各有一份缓存，
# 多进程部署时"改了 A 进程的缓存，B 进程看不到"——必须换 Redis。

# ---- 日志：生产必须结构化（课 18）----
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"()": "config.logfmt.JsonFormatter"},
    },
    "filters": {
        "trace": {"()": "apps.common.logging_filters.TraceIdFilter"},
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "json",
            "filters": ["trace"],
        },
    },
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "django": {"handlers": ["console"], "level": "INFO", "propagate": False},
        "django.request": {"handlers": ["console"], "level": "ERROR", "propagate": False},
        "shop": {"handlers": ["console"], "level": "INFO", "propagate": False},
    },
}

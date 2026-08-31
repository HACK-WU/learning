# -*- coding: utf-8 -*-
"""
Django 项目设置（简化版，聚焦 Celery 相关配置）

生产项目请拆分为 settings/base.py / dev.py / prod.py。
这里为了教学清晰，合并成一个文件。
"""
import os

from .settings_celery import *  # noqa: F401,F403  导入 Celery 配置

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SECRET_KEY = 'demo-only-change-in-production'
DEBUG = True
ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'django.contrib.contenttypes',
    'django.contrib.auth',
    'orders',                    # 本项目应用
]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': os.path.join(BASE_DIR, 'db.sqlite3'),
    }
}

USE_TZ = True
TIME_ZONE = 'Asia/Shanghai'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

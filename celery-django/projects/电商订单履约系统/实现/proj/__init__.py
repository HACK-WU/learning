"""Celery app 的显式加载入口。

作用：确保 Django 启动时 Celery app 也被加载（信号钩子注册生效）
"""
from .celery import app as celery_app

__all__ = ('celery_app',)

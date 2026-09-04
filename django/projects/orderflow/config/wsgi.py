"""WSGI 入口（课 22：进程模型的落点）。

生产用 waitress 启动时指向这里：
    waitress-serve --host=127.0.0.1 --port=8000 config.wsgi:application
"""
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

application = get_wsgi_application()

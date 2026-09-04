#!/usr/bin/env python
"""Django 管理入口。"""
import os
import sys


def main():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Django 没装或虚拟环境不对。\n"
            "本项目的验证环境：C:\\Users\\<你>\\.workbuddy\\binaries\\python\\envs\\dj-course"
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# 清理实战项目目录里的运行时产物（测试产生的 db / 日志 / pid / 缓存）
set -u
BASE="/mnt/d/projects/learning/celery-django/projects/电商订单履约系统/实现"

cd "$BASE" || exit 0

rm -f db.sqlite3
rm -rf logs
find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find . -type f -name '*.pyc' -delete 2>/dev/null || true

echo "清理完成，剩余文件："
find . -type f | sort
exit 0

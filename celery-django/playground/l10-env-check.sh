#!/usr/bin/env bash
set -u
echo "=== Python / 版本 ==="
/tmp/l9venv/bin/python --version
echo
echo "=== 已装关键依赖 ==="
/tmp/l9venv/bin/pip list 2>/dev/null | grep -iE 'celery|kombu|django|redis|flower|billiard|sqlalchemy' || true
echo
echo "=== Redis 是否可用 ==="
redis-cli -p 6380 ping 2>/dev/null || echo "6380 未响应"
redis-cli -p 6379 ping 2>/dev/null || echo "6379 未响应"
echo
echo "=== 磁盘/内存概况 ==="
free -m | head -2
df -h /tmp | tail -1
echo
echo "=== playground 现有哪些项目 ==="
ls /mnt/d/projects/learning/celery-django/playground/ 2>/dev/null || true
exit 0

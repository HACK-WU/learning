#!/usr/bin/env bash
set -u
echo "=== /tmp 下的 venv ==="
ls -d /tmp/*venv* 2>/dev/null || echo "(无 venv)"
echo
echo "=== 是否有 celery / django 可直接使用 ==="
which celery 2>/dev/null || echo "celery 不在 PATH"
which redis-server 2>/dev/null || echo "redis-server 不在 PATH"
echo
echo "=== wsl 里 python3 版本 ==="
python3 --version 2>/dev/null || echo "(无 python3)"
echo
echo "=== 尝试用 apt 装的 python 找已安装包 ==="
python3 -c "import celery, django; print('celery', celery.__version__); print('django', django.get_version())" 2>&1 | head -3
echo
echo "=== Redis 是否在运行 ==="
redis-cli -p 6380 ping 2>&1 | head -2
echo
echo "=== 之前课程的 venv 线索 ==="
ls /tmp/ 2>/dev/null | head -30
exit 0

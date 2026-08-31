#!/usr/bin/env bash
# 重建验证环境（/tmp 被系统清理了，这次把 venv 放在工作区里避免再次丢失）
set -u

VENV=/mnt/d/projects/learning/celery-django/.venv

echo "=== 1. 创建 venv（放在工作区，不用 /tmp）==="
if [ -d "$VENV" ]; then
  echo "    venv 已存在"
else
  python3 -m venv "$VENV" 2>&1 | tail -3
  echo "    venv 已创建"
fi

echo
echo "=== 2. 安装依赖 ==="
"$VENV/bin/pip" install -q --disable-pip-version-check \
    celery==5.6.3 django==6.1 redis requests flower 2>&1 | tail -5 || true

echo
echo "=== 3. 确认版本 ==="
"$VENV/bin/python" -c "
import celery, django, redis
print('celery', celery.__version__)
print('django', django.get_version())
print('redis ', redis.__version__)
" 2>&1

echo
echo "=== 4. 启动 Redis（6380）==="
if redis-cli -p 6380 ping > /dev/null 2>&1; then
  echo "    Redis 已在运行"
else
  redis-server --port 6380 --daemonize yes 2>&1 | tail -2 || \
    sudo redis-server --port 6380 --daemonize yes 2>&1 | tail -2 || true
  sleep 3
  redis-cli -p 6380 ping 2>&1 | head -1
fi

echo
echo "==============================================="
echo "环境重建完成"
echo "  venv: $VENV"
echo "==============================================="
exit 0

#!/usr/bin/env bash
# 取证：kombu 的 visibility_timeout 到底怎么实现的？为什么本机没复现"长任务被重投"？
set -u
PY=/mnt/d/projects/learning/celery-django/.venv/bin/python

echo "=== kombu 版本 ==="
"$PY" -c "import kombu; print('kombu', kombu.__version__)"

echo
echo "=== redis 传输层源码路径 ==="
REDIS_PY=$("$PY" -c "import kombu.transport.redis as m; print(m.__file__)")
echo "$REDIS_PY"

echo
echo "=== visibility_timeout 相关代码 ==="
grep -n "visibility_timeout" "$REDIS_PY" | head -30

echo
echo "=== 关键：restore / _restore / 续期逻辑 ==="
grep -n "def _restore\|def restore\|_zadd\|ZADD\|zadd\|unacked\|def _qsize\|ack_emulation" "$REDIS_PY" | head -30

echo
echo "=== kombu 版本里有没有 visibility 续期（heartbeat/interval）==="
grep -n "visibility" "$REDIS_PY" -A 3 | head -60

exit 0

#!/usr/bin/env bash
# 取证：ack_emulation 的默认值 & 为什么长任务没被重投
set -u
PY=/mnt/d/projects/learning/celery-django/.venv/bin/python
REDIS_PY=/mnt/d/projects/learning/celery-django/.venv/lib/python3.12/site-packages/kombu/transport/redis.py

echo "=== 1. Channel 默认配置（ack_emulation 默认是什么）==="
sed -n '630,700p' "$REDIS_PY"

echo
echo "=== 2. 我实验里实际生效的配置 ==="
"$PY" - <<'PYEOF'
from kombu.transport.redis import Channel
print('默认 ack_emulation      =', Channel.ack_emulation)
print('默认 visibility_timeout =', Channel.visibility_timeout)
print('默认 unacked_restore_limit =', getattr(Channel, 'unacked_restore_limit', 'N/A'))
PYEOF

echo
echo "=== 3. Celery 侧：task_acks_late 如何映射到 ack_emulation ==="
CELERY_DIR=$("$PY" -c "import celery, os; print(os.path.dirname(celery.__file__))")
grep -rn "ack_emulation" "$CELERY_DIR" 2>/dev/null | head -10 || echo "(celery 侧未出现 ack_emulation)"

echo
echo "=== 4. kombu 里 QoS.restore_visible 被谁调用（多久跑一次）==="
grep -n "restore_visible" "$REDIS_PY" | head
echo "--- 在 poller 里的调用点 ---"
grep -n "restore_visible\|on_poll_start\|maybe_restore" "$REDIS_PY" | head -20

echo
echo "=== 5. restore_visible 完整实现（看它到底恢复什么）==="
sed -n '410,432p' "$REDIS_PY"

exit 0

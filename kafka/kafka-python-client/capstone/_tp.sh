#!/bin/bash
# 权威吞吐测量：停掉服务，排除同容器 CPU 竞争与同组 rebalance
echo "=== 停掉服务 ==="
docker exec capstone-svc sh -c 'for p in $(ls /proc | grep -E "^[0-9]+$"); do
  [ -r /proc/$p/cmdline ] || continue
  c=$(tr "\0" " " < /proc/$p/cmdline 2>/dev/null)
  case "$c" in */app/.venv/bin/python*uvicorn*) kill -9 $p 2>/dev/null && echo "  killed $p";; esac
done'
sleep 5
echo "=== 干净测吞吐（3 轮，每轮 2000 条，独立 group）==="
docker exec -w /app/capstone capstone-svc env PYTHONIOENCODING=utf-8 \
  /app/.venv/bin/python tests/_throughput.py

#!/bin/bash
# 验证假设：慢是"测试脚本与运行中的服务共用 group.id 触发持续 rebalance"
# 做法：停掉 capstone-svc 服务，再跑同一个 _line_bench.py
# 若全组都快 -> 假设成立，代码无性能问题
echo "=== 停掉服务（保留容器）==="
docker exec capstone-svc sh -c 'for p in $(ls /proc | grep -E "^[0-9]+$"); do
  [ -r /proc/$p/cmdline ] || continue
  c=$(tr "\0" " " < /proc/$p/cmdline 2>/dev/null)
  case "$c" in */app/.venv/bin/python*uvicorn*) kill -9 $p 2>/dev/null && echo "  killed $p";; esac
done'
sleep 5
echo "=== 确认服务已停 ==="
docker exec capstone-svc /app/.venv/bin/python -c "
import urllib.request,urllib.error
try:
    urllib.request.urlopen('http://localhost:8000/health',timeout=5)
    print('  服务仍在')
except Exception as e:
    print('  服务已停:',type(e).__name__)
"
echo
echo "=== 重跑 _line_bench（无服务抢组）==="
docker exec -w /app/capstone capstone-svc env PYTHONIOENCODING=utf-8 \
  /app/.venv/bin/python tests/_line_bench.py

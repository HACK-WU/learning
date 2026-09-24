#!/bin/bash
# 课13 服务管理：用 PID 文件精确管理，避免 /proc 扫描误杀自身
# 背景：slim 镜像无 ps/pkill；用 /proc 扫描时执行脚本的 sh -c 自身
#      cmdline 也含匹配串，会误杀自己、漏杀目标（实测踩过）。
PIDFILE=/tmp/capstone-svc.pid

echo "=== 停止旧实例 ==="
if [ -f /tmp/cap13_pid ]; then
  docker exec l11 sh -c "kill -9 \$(cat /tmp/cap13_pid) 2>/dev/null; echo stopped"
fi
# 兜底：杀所有匹配精确进程（排除 sh -c）
docker exec l11 sh -c 'for p in $(ls /proc | grep -E "^[0-9]+$"); do
  [ -r /proc/$p/cmdline ] || continue
  c=$(tr "\0" " " < /proc/$p/cmdline 2>/dev/null)
  case "$c" in
    "/app/.venv/bin/uvicorn app.main:app"*) kill -9 $p 2>/dev/null ;;
    "/app/.venv/bin/python /app/.venv/bin/uvicorn app.main:app"*) kill -9 $p 2>/dev/null ;;
  esac
done'
sleep 3

echo "=== 确认已清空 ==="
N=$(docker exec l11 sh -c 'n=0; for p in $(ls /proc | grep -E "^[0-9]+$"); do
  [ -r /proc/$p/cmdline ] || continue
  c=$(tr "\0" " " < /proc/$p/cmdline 2>/dev/null)
  case "$c" in *"uvicorn app.main:app"*) n=$((n+1));; esac
done; echo $n')
echo "  匹配进程数 = $N （应为 0）"

echo "=== 启动新实例 ==="
docker exec -d -w /app/capstone l11 env PYTHONPATH=/app PYTHONUNBUFFERED=1 \
  /app/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
sleep 14

echo "=== 验证 ==="
docker exec l11 python3 - <<'EOF' 2>&1
import json, urllib.request, urllib.error
try:
    with urllib.request.urlopen("http://localhost:8000/ready", timeout=20) as r:
        print("  ready:", json.loads(r.read().decode()))
except urllib.error.HTTPError as e:
    print("  503 未就绪:", e.read().decode()[:200])
except Exception as e:
    print("  异常:", type(e).__name__, e)
with urllib.request.urlopen("http://localhost:8000/stats", timeout=20) as r:
    s = json.loads(r.read().decode())
print(f"  分区 lag: {s.get('lag_by_partition')}  合计={s.get('lag_total')}")
EOF

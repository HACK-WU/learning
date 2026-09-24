#!/bin/bash
# 课13 L2 集成实测：真服务 + 真集群
# 在 l11 容器里起 uvicorn，然后打真实 HTTP 端点
docker exec l11 pkill -f "uvicorn app.main" 2>/dev/null
sleep 1
docker exec -d -w /app/capstone l11 env PYTHONPATH=/app PYTHONUNBUFFERED=1 \
  /app/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
echo "  服务启动中…"
sleep 12
echo "=== /health ==="
docker exec l11 python3 -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/health').read().decode())" 2>&1 | head -3
echo "=== /ready ==="
docker exec l11 python3 -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/ready').read().decode())" 2>&1 | head -3

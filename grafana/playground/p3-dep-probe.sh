#!/bin/bash
echo "=== 1. WSL 里的 Python 与 pip ==="
python3 --version 2>&1
which pip3 pip 2>&1
echo

echo "=== 2. uv 是否可用（不擅自安装）==="
which uv 2>&1 || echo "  uv 未安装"
echo

echo "=== 3. 现有 Python 包里有没有需要的 ==="
python3 -c "import prometheus_client; print('  prometheus_client: 有', prometheus_client.__version__)" 2>&1 | head -2
python3 -c "import opentelemetry; print('  opentelemetry: 有')" 2>&1 | head -2
python3 -c "import flask; print('  flask: 有')" 2>&1 | head -2
echo

echo "=== 4. 容器内是否已有可复用的 Python 镜像 ==="
docker images --format '{{.Repository}}:{{.Tag}}' | grep -Ei 'python|otel|prom' | head -10
echo

echo "=== 5. 检查已跑的 demo 应用是怎么造指标的（l3-app / l7-app / l8-app）==="
for C in l3-app l7-app l8-app demo-app; do
  echo "  --- $C ---"
  docker inspect $C --format '  镜像={{.Config.Image}}  命令={{.Config.Cmd}}' 2>&1 | head -2
done
echo

echo "=== 6. capstone 系列（看起来是现成的 otel 演练应用）==="
for C in capstone-agent capstone-gateway; do
  echo "  --- $C ---"
  docker inspect $C --format '  镜像={{.Config.Image}}' 2>&1
done
echo

echo "=== 7. 有没有现成的 otel demo 镜像 ==="
docker images --format '{{.Repository}}:{{.Tag}}' | head -40

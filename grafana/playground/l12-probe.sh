#!/bin/bash
echo "=== 1. 现有容器 ==="
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' | grep -Ei 'grafana|postgres|mysql|prom|loki|jaeger' || echo "  none"
echo

echo "=== 2. 本机已有镜像（grafana/postgres/mysql）==="
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -Ei 'grafana|postgres|mysql' || echo "  none"
echo

echo "=== 3. 3001/3002/3003 健康 ==="
for p in 3001 3002 3003; do
  printf "  %s: " "$p"
  curl -s --noproxy '*' -m 5 http://localhost:$p/api/health | tr -d ' \n'
  echo
done
echo

echo "=== 4. 磁盘剩余 ==="
df -h / | tail -1
echo

echo "=== 5. 试拉 postgres:16-alpine（限时 120s）==="
timeout 120 docker pull postgres:16-alpine 2>&1 | tail -5
echo "  pull exit=$?"

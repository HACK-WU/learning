#!/bin/bash
echo "=== 1. 5432 谁在占用 ==="
docker ps -a --format '{{.Names}}\t{{.Ports}}' | grep -E '5432' || echo "  docker 容器未占用"
echo "  --- 宿主机监听 ---"
(ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | grep 5432 || echo "  无 ss/netstat 或无监听"
echo

echo "=== 2. grafana-lab 网络模式 ==="
docker inspect grafana-lab --format '{{.HostConfig.NetworkMode}}'
echo

echo "=== 3. 现有 docker 网络 ==="
docker network ls --format '{{.Name}}\t{{.Driver}}'
echo

echo "=== 4. 用 5433 重建 Postgres ==="
docker rm -f l12-pg >/dev/null 2>&1
docker run -d --name l12-pg -p 5433:5432 -e POSTGRES_PASSWORD=grafana -e POSTGRES_USER=grafana -e POSTGRES_DB=grafana postgres:16-alpine 2>&1 | tail -2
sleep 10
docker exec l12-pg pg_isready -U grafana 2>&1
docker exec l12-pg psql -U grafana -d grafana -tAc 'select version();' 2>&1 | head -2
echo

echo "=== 5. 从 WSL 宿主连 5433 ==="
PGPASSWORD=grafana psql -h 127.0.0.1 -p 5433 -U grafana -d grafana -tAc 'select 1;' 2>&1 | head -3 || echo "  (WSL 未装 psql 客户端，忽略)"

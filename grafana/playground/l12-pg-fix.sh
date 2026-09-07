#!/bin/bash
echo "=== Postgres 启动失败日志 ==="
docker logs l12-pg 2>&1 | tail -20
echo
echo "=== 清理并用桥接网络重建（映射 5432）==="
docker rm -f l12-pg >/dev/null 2>&1
docker run -d --name l12-pg -p 5432:5432 -e POSTGRES_PASSWORD=grafana -e POSTGRES_USER=grafana -e POSTGRES_DB=grafana postgres:16-alpine 2>&1 | tail -2
sleep 10
echo "  --- pg_isready ---"
docker exec l12-pg pg_isready -U grafana 2>&1
echo "  --- 端口探测 ---"
docker exec l12-pg psql -U grafana -d grafana -c 'select version();' 2>&1 | head -3

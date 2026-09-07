#!/bin/bash
echo "=== 1. 拉 grafana 12.0.0（升级/降级实验用，限时 300s）==="
timeout 300 docker pull grafana/grafana:12.0.0 2>&1 | tail -3
echo

echo "=== 2. 起 Postgres 16 ==="
docker rm -f l12-pg >/dev/null 2>&1
docker run -d --name l12-pg --network host -e POSTGRES_PASSWORD=grafana -e POSTGRES_USER=grafana -e POSTGRES_DB=grafana postgres:16-alpine 2>&1 | tail -2
sleep 8
docker exec l12-pg pg_isready -U grafana 2>&1
echo

echo "=== 3. grafana-lab(3001) 当前数据库类型 ==="
docker exec grafana-lab printenv | grep -Ei 'GF_DATABASE|GF_INSTALL|GF_AUTH' | sort
echo "  --- 数据库相关环境变量（上面若无输出则说明用默认 sqlite）---"
echo

echo "=== 4. grafana-lab 数据目录 ==="
docker exec grafana-lab ls -la /var/lib/grafana/ 2>&1 | head -20
echo

echo "=== 5. grafana.db 大小 ==="
docker exec grafana-lab du -h /var/lib/grafana/grafana.db 2>&1
echo

echo "=== 6. provisioning 目录挂载情况 ==="
docker inspect grafana-lab --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>&1
echo

echo "=== 7. 镜像版本信息 ==="
docker exec grafana-lab grafana --version 2>&1 | head -3

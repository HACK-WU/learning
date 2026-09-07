#!/bin/bash
echo "=== 1. 建专用网络 ==="
docker network create l12net 2>&1 | tail -1
echo

echo "=== 2. 把 pg 接入 l12net ==="
docker network connect l12net l12-pg 2>&1 | tail -1
echo

echo "=== 3. 起 grafana-pg-1（3004，连 Postgres）==="
docker rm -f gf-pg1 >/dev/null 2>&1
docker run -d --name gf-pg1 --network l12net -p 3004:3000 \
  -e GF_DATABASE_TYPE=postgres \
  -e GF_DATABASE_HOST=l12-pg:5432 \
  -e GF_DATABASE_NAME=grafana \
  -e GF_DATABASE_USER=grafana \
  -e GF_DATABASE_PASSWORD=grafana \
  -e GF_DATABASE_SSL_MODE=disable \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:13.2.1 2>&1 | tail -2
echo

echo "=== 4. 等待启动（最多 120s）==="
for i in $(seq 1 60); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3004/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s: $R"; break; fi
  sleep 2
done
echo

echo "=== 5. 确认数据库类型 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3004/api/health 2>&1
echo
docker logs gf-pg1 2>&1 | grep -Ei 'database|postgres|migrat' | head -10
echo

echo "=== 6. Postgres 里生成的表数 ==="
docker exec l12-pg psql -U grafana -d grafana -tAc "select count(*) from information_schema.tables where table_schema='public';" 2>&1
echo

echo "=== 7. 对比 grafana-lab 的 sqlite 表数 ==="
docker exec grafana-lab sh -c 'ls -la /var/lib/grafana/grafana.db' 2>&1

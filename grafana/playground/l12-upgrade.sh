#!/bin/bash
echo "########## 跨版本实验：13.2.1 的库，12.0.0 能开吗 ##########"
echo

echo "=== 0. 先给当前 Postgres 库做快照备份 ==="
docker exec l12-pg pg_dump -U grafana -d grafana > /tmp/gf_before_downgrade.sql 2>/dev/null
echo "  备份大小=$(wc -c < /tmp/gf_before_downgrade.sql) 字节"
echo "  --- 当前 migration_log 数 ---"
docker exec l12-pg psql -U grafana -d grafana -tAc "select count(*) from migration_log;"
echo

echo "=== 1. 停掉 13.2.1 的两个实例（防止并发改库）==="
docker stop gf-pg1 gf-pg2 2>&1 | tail -2
echo

echo "=== 2. 用 12.0.0 起一个实例，指向同一个库（3007）==="
docker rm -f gf-old >/dev/null 2>&1
docker run -d --name gf-old --network l12net -p 3007:3000 \
  -e GF_DATABASE_TYPE=postgres \
  -e GF_DATABASE_HOST=l12-pg:5432 \
  -e GF_DATABASE_NAME=grafana \
  -e GF_DATABASE_USER=grafana \
  -e GF_DATABASE_PASSWORD=grafana \
  -e GF_DATABASE_SSL_MODE=disable \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:12.0.0 2>&1 | tail -1
sleep 25
echo "  容器状态: $(docker ps -a --filter name=gf-old --format '{{.Status}}')"
echo

echo "=== 3. 12.0.0 启动日志的关键部分 ==="
docker logs gf-old 2>&1 | grep -Ei 'error|migrat|fail|panic|warn' | tail -15
echo

echo "=== 4. 12.0.0 能起来吗（健康检查）==="
curl -s --noproxy '*' -m 10 http://localhost:3007/api/health -w '\n  health_http=%{http_code}\n' 2>&1
echo

echo "=== 5. 数据库被改了吗（migration_log 是否被回退）==="
echo "  降级后 migration_log 数: $(docker exec l12-pg psql -U grafana -d grafana -tAc 'select count(*) from migration_log;')"
echo

echo "=== 6. 降级的真实报错全文 ==="
docker logs gf-old 2>&1 | tail -25

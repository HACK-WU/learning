#!/bin/bash
echo "########## 降级后数据还完整吗 ##########"
echo

echo "=== 1. 降级前建的 dashboard 还在吗 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3007/api/dashboards/uid/ha-probe -o /tmp/dg1.json -w '  ha-probe(pg1建的)=%{http_code}\n'
head -c 200 /tmp/dg1.json
echo
echo

echo "=== 2. 服务账号 token 还在吗 ==="
docker exec l12-pg psql -U grafana -d grafana -tAc "select id,name,left(key,20) from api_key;"
echo

echo "=== 3. 12.0.0 跑的那 12 条迁移是什么 ==="
docker exec l12-pg psql -U grafana -d grafana -tAc "select migration_id from migration_log order by id desc limit 12;"
echo

echo "=== 4. 现在把 13.2.1 接回来，它还能开吗（验证是否真的能回滚）==="
docker stop gf-old >/dev/null 2>&1
docker start gf-pg1 >/dev/null 2>&1
sleep 25
echo "  13.2.1 状态: $(docker ps -a --filter name=gf-pg1 --format '{{.Status}}')"
curl -s --noproxy '*' -m 15 http://localhost:3004/api/health -w '\n  health=%{http_code}\n' 2>&1
echo "  --- 13.2.1 启动日志关键 ---"
docker logs gf-pg1 2>&1 | tail -8 | grep -Ei 'error|migrat|version|fail' | head -8
echo

echo "=== 5. 回滚后数据完整性 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3004/api/dashboards/uid/ha-probe -o /dev/null -w '  ha-probe=%{http_code}\n'
curl -s --noproxy '*' -u admin:admin http://localhost:3004/api/dashboards/uid/ha-probe2 -o /dev/null -w '  ha-probe2=%{http_code}\n'
echo "  migration_log 现在: $(docker exec l12-pg psql -U grafana -d grafana -tAc 'select count(*) from migration_log;')"
echo

echo "=== 6. 用真备份恢复测试（验证备份有效性）==="
echo "  --- 建一个新库 gf_restore ---"
docker exec l12-pg psql -U grafana -d postgres -tAc "drop database if exists gf_restore;" >/dev/null 2>&1
docker exec l12-pg psql -U grafana -d postgres -tAc "create database gf_restore;" 2>&1
docker exec -i l12-pg psql -U grafana -d gf_restore < /tmp/gf_before_downgrade.sql > /tmp/restore.log 2>&1
echo "  恢复 exit=$?"
echo "  --- 恢复后表数 ---"
docker exec l12-pg psql -U grafana -d gf_restore -tAc "select count(*) from information_schema.tables where table_schema='public';"
echo "  --- 恢复后 migration_log ---"
docker exec l12-pg psql -U grafana -d gf_restore -tAc "select count(*) from migration_log;"
echo "  --- 恢复后 api_key ---"
docker exec l12-pg psql -U grafana -d gf_restore -tAc "select id,name,left(key,20) from api_key;"
echo

echo "=== 7. 用恢复的库起一个 Grafana（3008）验证可用性 ==="
docker rm -f gf-restore >/dev/null 2>&1
docker run -d --name gf-restore --network l12net -p 3008:3000 \
  -e GF_DATABASE_TYPE=postgres -e GF_DATABASE_HOST=l12-pg:5432 \
  -e GF_DATABASE_NAME=gf_restore -e GF_DATABASE_USER=grafana \
  -e GF_DATABASE_PASSWORD=grafana -e GF_DATABASE_SSL_MODE=disable \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:13.2.1 2>&1 | tail -1
sleep 25
curl -s --noproxy '*' -m 15 http://localhost:3008/api/health -w '\n  restored_health=%{http_code}\n' 2>&1
echo "  --- 恢复的库里 dashboard 在吗 ---"
curl -s --noproxy '*' -u admin:admin http://localhost:3008/api/dashboards/uid/ha-probe -o /dev/null -w '  ha-probe_on_restored=%{http_code}\n'

#!/bin/bash
echo "########## 备份全景：Grafana 到底有哪些东西要备份 ##########"
echo

echo "=== 1. Postgres 后端：数据库里有什么 ==="
echo "  --- 表总数 ---"
docker exec l12-pg psql -U grafana -d grafana -tAc "select count(*) from information_schema.tables where table_schema='public';"
echo "  --- 最大的几张表（数据量排序）---"
docker exec l12-pg psql -U grafana -d grafana -tAc "select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc limit 8;"
echo

echo "=== 2. 备份方式 A：pg_dump（逻辑备份）==="
docker exec l12-pg pg_dump -U grafana -d grafana > /tmp/gf_backup.sql 2>/tmp/pgdump.err
echo "  exit=$? 大小=$(wc -c < /tmp/gf_backup.sql) 字节"
echo "  stderr: $(head -2 /tmp/pgdump.err)"
echo "  --- 备份文件头部 ---"
head -5 /tmp/gf_backup.sql
echo

echo "=== 3. 关键发现核对：token 在数据库里是什么形态 ==="
echo "  --- 服务账号 token 表 ---"
docker exec l12-pg psql -U grafana -d grafana -tAc "\d api_key" 2>&1 | head -12
echo "  --- 实际存的内容 ---"
docker exec l12-pg psql -U grafana -d grafana -tAc "select name, left(key,20) as key_prefix, left(hashed_key,30) as hash_prefix from api_key limit 5;" 2>&1
echo

echo "=== 4. SQLite 后端的文件清单（grafana-lab）==="
docker exec grafana-lab sh -c 'find /var/lib/grafana -maxdepth 1 -type f -o -maxdepth 1 -type d | sort' 2>&1
echo

echo "=== 5. 配置文件在哪（grafana.ini / provisioning）==="
docker exec grafana-lab ls -la /etc/grafana/ 2>&1 | head
echo "  --- provisioning 目录 ---"
docker exec grafana-lab ls -la /etc/grafana/provisioning/ 2>&1 | head
echo

echo "=== 6. 密钥：secret_key 存在哪（备份漏了它，恢复后登录态全掉）==="
docker exec l12-pg psql -U grafana -d grafana -tAc "select name, left(value,25) from kv_store where name like '%secret%' or name like '%token%' limit 10;" 2>&1
echo "  --- kv_store 里所有 key 的前 20 个 ---"
docker exec l12-pg psql -U grafana -d grafana -tAc "select distinct name from kv_store limit 20;" 2>&1

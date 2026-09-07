#!/bin/bash
PG="docker exec l12-pg psql -U grafana -d grafana -tAc"

echo "=== 1. api_key 表里到底存了什么（课 11 结论核实）==="
echo "  --- 记录数 ---"
$PG "select count(*) from api_key;"
echo "  --- 内容（key 列前 24 字符）---"
$PG "select id, name, left(key,24), role, service_account_id from api_key limit 5;"
echo

echo "=== 2. kv_store 表结构 ==="
$PG "\d kv_store" 2>&1 | head -12
echo "  --- 内容 ---"
$PG "select * from kv_store limit 8;" 2>&1 | head -12
echo

echo "=== 3. migration_log：schema 版本历史（升级的关键）==="
echo "  --- 总迁移数 ---"
$PG "select count(*) from migration_log;"
echo "  --- 最后 5 条迁移 ---"
$PG "select migration_id, sql from migration_log order by id desc limit 5;" 2>&1 | head -8
echo

echo "=== 4. 哪些表存了 dashboard / datasource / user（备份的核心资产）==="
echo "  --- 找 dashboard 相关表 ---"
$PG "select table_name from information_schema.tables where table_schema='public' and (table_name like '%dashboard%' or table_name like '%datasource%' or table_name like '%user%') order by table_name;" 2>&1
echo

echo "=== 5. dashboard 表内容 ==="
$PG "select uid, title from dashboard limit 6;" 2>&1
echo "  --- datasource 表 ---"
$PG "select uid, name, type from data_source limit 6;" 2>&1
echo

echo "=== 6. 建一个服务账号 token，看它落库成什么（关键实验）==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/serviceaccounts -H 'Content-Type: application/json' -d '{"name":"bk-test-sa","role":"Viewer"}' -o /tmp/sa.json -w '  create_sa=%{http_code}\n'
SAID=$(python3 -c "import json;print(json.load(open('/tmp/sa.json')).get('id',''))" 2>/dev/null)
echo "  sa_id=$SAID"
if [ -n "$SAID" ]; then
  TOK=$(curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/serviceaccounts/$SAID/tokens -H 'Content-Type: application/json' -d '{"name":"bk-token"}')
  echo "  创建 token 返回: $(echo $TOK | head -c 200)"
  echo "$TOK" > /tmp/tok.json
  echo "  --- 落库后 api_key 表 ---"
  $PG "select id, name, left(key,30), service_account_id, is_revoked from api_key order by id desc limit 3;"
fi

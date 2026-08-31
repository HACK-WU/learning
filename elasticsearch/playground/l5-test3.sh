#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 15. dynamic:false（索引名全小写）##########"
$C -X DELETE "$ES/l5_nodyn" > /dev/null 2>&1
$C -X PUT "$ES/l5_nodyn" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"dynamic":false,"properties":{"title":{"type":"text"}}}}'
echo ""
echo "--- 写入未知字段（不报错，接受写入）---"
$C -X POST "$ES/l5_nodyn/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "title":"测试","ghost":"我是幽灵字段"}'
echo ""
echo "--- 映射里没有 ghost ---"
$C "$ES/l5_nodyn/_mapping"
echo ""
echo "--- 但 _source 里能看到它（存了但搜不到）---"
$C "$ES/l5_nodyn/_doc/1"
echo ""
echo "--- 搜 ghost：0 条 ---"
$C -X POST "$ES/l5_nodyn/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"match":{"ghost":"幽灵"}}}'
echo ""

echo "########## 16. 改映射的正确姿势：新建索引 + reindex ##########"
echo "--- 旧索引 l5_trap 的 price 是 text（错误类型）---"
$C "$ES/l5_trap/_mapping"
echo ""
echo "--- 新建正确索引 price 为 float ---"
$C -X DELETE "$ES/l5_trap_v2" > /dev/null 2>&1
$C -X PUT "$ES/l5_trap_v2" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{"price":{"type":"float"}}}}'
echo ""
echo "--- reindex 迁移 ---"
$C -X POST "$ES/_reindex?refresh=true" -H "Content-Type: application/json" -d '{
  "source":{"index":"l5_trap"},"dest":{"index":"l5_trap_v2"}}'
echo ""
echo "--- 验证新索引 price 类型为 float ---"
$C "$ES/l5_trap_v2/_mapping"
echo ""
echo "--- range 查询 price>=10（现在语义正确了）---"
$C -X POST "$ES/l5_trap_v2/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"range":{"price":{"gte":10}}}}'
echo ""
echo "########## DONE ##########"

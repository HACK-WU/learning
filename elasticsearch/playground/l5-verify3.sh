#!/bin/bash
# 端到端验证：第四幕第 3-4 步（l5_wrong / l5_right）真能跑通
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "### 第3步：建错误索引 brand=text，写入，聚合报错 ###"
$C -X DELETE "$ES/l5_wrong" > /dev/null 2>&1
$C -X PUT "$ES/l5_wrong" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{"brand":{"type":"text"}}}}'
echo ""
$C -X POST "$ES/l5_wrong/_doc?refresh=true" -H "Content-Type: application/json" -d '{"brand":"Apple"}'
echo ""
echo "-- 聚合 --"
$C -X POST "$ES/l5_wrong/_search" -H "Content-Type: application/json" -d '{
  "size":0,"aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | head -c 260
echo ""

echo ""
echo "### 第4步：新建正确索引 + reindex + 聚合成功 ###"
$C -X DELETE "$ES/l5_right" > /dev/null 2>&1
$C -X PUT "$ES/l5_right" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "brand":{"type":"keyword"},
    "price":{"type":"scaled_float","scaling_factor":100}}}}'
echo ""
$C -X POST "$ES/_reindex?refresh=true" -H "Content-Type: application/json" -d '{
  "source":{"index":"l5_wrong"},"dest":{"index":"l5_right"}}'
echo ""
echo "-- 再聚合 --"
$C -X POST "$ES/l5_right/_search" -H "Content-Type: application/json" -d '{
  "size":0,"aggs":{"by_brand":{"terms":{"field":"brand"}}}}'
echo ""

echo "### 第5步：strict 与 nodyn ###"
$C -X DELETE "$ES/l5_strict" > /dev/null 2>&1
$C -X PUT "$ES/l5_strict" -H "Content-Type: application/json" -d '{
  "mappings":{"dynamic":"strict","properties":{"title":{"type":"text"}}}}'
echo ""
$C -X POST "$ES/l5_strict/_doc/1" -H "Content-Type: application/json" -d '{
  "title":"测试","unknown":"我不该进来"}' | head -c 220
echo ""

$C -X DELETE "$ES/l5_nodyn" > /dev/null 2>&1
$C -X PUT "$ES/l5_nodyn" -H "Content-Type: application/json" -d '{
  "mappings":{"dynamic":false,"properties":{"title":{"type":"text"}}}}'
echo ""
$C -X POST "$ES/l5_nodyn/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "title":"测试","ghost":"幽灵字段"}' | head -c 120
echo ""
echo "-- 搜 ghost --"
$C -X POST "$ES/l5_nodyn/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"match":{"ghost":"幽灵"}}}'
echo ""
echo "########## DONE ##########"

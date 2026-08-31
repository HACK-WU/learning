#!/bin/bash
# 评审修正：补测开场场景的真实报错 + long 截断小数的行为
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## A. 开场场景真实复现：brand 是 text，做聚合 ##########"
$C -X DELETE "$ES/l5_shop_bad" > /dev/null 2>&1
$C -X PUT "$ES/l5_shop_bad" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "name":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart"},
    "brand":{"type":"text"},
    "price":{"type":"long"}}}}'
echo ""
$C -X POST "$ES/l5_shop_bad/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "name":"苹果手机 iPhone 15","brand":"Apple","price":7999}'
echo ""
echo "--- 对 brand(text) 做 terms 聚合 ---"
$C -X POST "$ES/l5_shop_bad/_search" -H "Content-Type: application/json" -d '{
  "size":0,"aggs":{"by_brand":{"terms":{"field":"brand"}}}}'
echo ""

echo "########## B. long 字段写入小数 19.9 会怎样？##########"
$C -X POST "$ES/l5_shop_bad/_doc/2?refresh=true" -H "Content-Type: application/json" -d '{
  "name":"测试商品","brand":"Test","price":19.9}'
echo ""
echo "--- 读回来看存成了什么 ---"
$C "$ES/l5_shop_bad/_doc/2?filter_path=_source"
echo ""

echo "########## C. date 字段写中文（已测，复核）##########"
$C -X DELETE "$ES/l5_datecheck" > /dev/null 2>&1
$C -X PUT "$ES/l5_datecheck" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{"created_at":{"type":"date"}}}}'
echo ""
$C -X POST "$ES/l5_datecheck/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "created_at":"昨天"}'
echo ""
echo "########## DONE ##########"

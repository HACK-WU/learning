#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "===== 抓取 l8_text_demo 的详细报错（含 failed_shards）====="
$C -X POST "$ES/l8_text_demo/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}'
echo ""
echo "===== 当前 fielddata 状态 ====="
$C "$ES/l8_text_demo/_mapping?pretty"
echo ""
echo "===== 尝试开启 fielddata 的完整返回 ====="
$C -X PUT "$ES/l8_text_demo/_mapping" -H "Content-Type: application/json" -d '{
  "properties":{"brand":{"type":"text","fielddata":true}}}'
echo ""
echo "===== 开启后再聚合 ====="
$C -X POST "$ES/l8_text_demo/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}'
echo ""
echo "########## DONE-L8-17 ##########"

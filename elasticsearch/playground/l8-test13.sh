#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"
IDX="l8_orders_v2"

echo "=== 问题1 原始返回（bucket_script 放顶层）==="
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{
    "by_brand":{"terms":{"field":"brand","size":10},
      "aggs":{"销售额":{"sum":{"field":"amount"}}}},
    "总销售额":{"sum":{"field":"amount"}},
    "占比":{"bucket_script":{"buckets_path":{"s":"销售额"},"script":"params.s"}}}}'
echo ""
echo "########## DONE-L8-13 ##########"

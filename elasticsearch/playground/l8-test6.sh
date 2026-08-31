#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== cumulative_sum 原始返回 ==="
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword","order":{"_key":"asc"}},
    "aggs":{
      "销售额":{"sum":{"field":"amount"}},
      "累计":{"cumulative_sum":{"buckets_path":"销售额"}}}}}}'
echo ""
echo "########## DONE-L8-6 ##########"

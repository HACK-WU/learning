#!/bin/bash
export LANG=C.UTF-8
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW -H Content-Type:application/json"
D="/mnt/d/projects/learning/elasticsearch/playground"
Q='{"size":0,"aggs":{"by_brand":{"terms":{"field":"brand","size":10},"aggs":{"s":{"sum":{"field":"amount"}},"a":{"avg":{"field":"unit_price"}}}}}}'

$C "https://localhost:9200/l8_orders_v2/_search?size=0" -d "$Q" > "$D/_r1.json"
echo "原始返回:"
cat "$D/_r1.json" | tr ',' '\n' | grep -E '"key"|"doc_count"|"value"' | head -20

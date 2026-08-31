#!/bin/bash
export LANG=C.UTF-8
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW -H Content-Type:application/json"
D="/mnt/d/projects/learning/elasticsearch/playground"

echo "===== 品牌: 销售额 / 均价(price) ====="
echo "期望: 苹果 80390 均价8849.0 | 华为 64179 均价6497.625 | 小米 45488 均价4236.5"
Q='{"size":0,"aggs":{"by_brand":{"terms":{"field":"brand","size":10},"aggs":{"s":{"sum":{"field":"amount"}},"a":{"avg":{"field":"price"}}}}}}'
$C "https://localhost:9200/l8_orders_v2/_search?size=0" -d "$Q" | tr ',' '\n' | grep -E '"key"|"doc_count"|"value"' | head -20

echo ""
echo "===== 讲义字段引用核对 ====="
L8="$D/../../stages/3-查询与聚合/lessons/lesson-08-聚合不做搜索做统计.md"
for f in brand category city price qty amount sale_date status tags product brand_text region salesman; do
  n=$(grep -c "$f" "$L8")
  echo "$f -> $n 次"
done

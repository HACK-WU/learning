#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 核心实验：对 text 字段做 terms 聚合会怎样？##########"
echo "--- A. 对 brand（当前是 text 类型）做 terms 聚合 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}'
echo ""
echo "--- B. 对 brand.keyword 做 terms 聚合 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   桶数:',len(d['aggregations']['by_brand']['buckets']))
for b in d['aggregations']['by_brand']['buckets']:
    print('     %-8s %s'%(b['key'],b['doc_count']))"
echo ""
echo "--- C. 对 brand_text（ik 分词）做 terms 聚合 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand_text"}}}}'
echo ""
echo "########## DONE-L8-3 ##########"

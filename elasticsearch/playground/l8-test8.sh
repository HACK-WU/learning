#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## ES|QL 中文列名限制验证 ##########"
echo "--- A. 中文别名（会报错）---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | STATS 订单数 = COUNT(*) BY brand"}'
echo ""
echo "--- B. 英文别名（正常）---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | STATS cnt = COUNT(*), total = SUM(amount), avg_price = AVG(price) BY brand | SORT total DESC"}'
echo ""

echo "--- C. 中文值可以，中文列名不行：用英文列名取中文值 ---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | WHERE brand == \"苹果\" | STATS cnt = COUNT(*), total = SUM(amount) | KEEP cnt, total"}'
echo ""

echo "--- D. ES|QL 分桶统计（对应 DSL terms）---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | STATS cnt = COUNT(*) BY category | SORT cnt DESC"}'
echo ""

echo "--- E. ES|QL 时间分桶（BUCKET）---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | STATS cnt = COUNT(*), total = SUM(amount) BY wk = BUCKET(sale_date, 1 week) | SORT wk ASC"}'
echo ""

echo "--- F. 对比：DSL 写法（同一问题）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_cat":{"terms":{"field":"category.keyword","size":10},
    "aggs":{"cnt":{"value_count":{"field":"order_id.keyword"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['by_cat']['buckets']:
    print('   %-6s %s 单'%(b['key'],b['doc_count']))"
echo ""
echo "########## DONE-L8-8 ##########"

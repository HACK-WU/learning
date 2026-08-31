#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 修正：cumulative_sum 必须挂在 histogram 类下 ##########"
echo "--- 按周累计销售额 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_week":{
    "date_histogram":{"field":"sale_date","calendar_interval":"week"},
    "aggs":{
      "周销售额":{"sum":{"field":"amount"}},
      "累计":{"cumulative_sum":{"buckets_path":"周销售额"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['by_week']['buckets']:
    print('   %s  本周=%-10s 累计=%s'%(b['key_as_string'][:10],b['周销售额']['value'],b['累计']['value']))"
echo ""

echo "--- 反例确认：terms 下用 cumulative_sum 的报错 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword"},
    "aggs":{"销售额":{"sum":{"field":"amount"}},
      "累计":{"cumulative_sum":{"buckets_path":"销售额"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   报错:',d.get('error',{}).get('reason','(无)'))"
echo ""

echo "########## 知识点3：ES|QL 入门 ##########"
echo "--- A. 最简单的 ES|QL：FROM + LIMIT ---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | LIMIT 5"}'
echo ""

echo "--- B. ES|QL 做聚合：STATS ... BY ---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | STATS 订单数 = COUNT(*), 总销售额 = SUM(amount), 平均单价 = AVG(price) BY brand"}'
echo ""

echo "--- C. ES|QL 排序 + 筛选 ---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | WHERE price > 8000 | SORT price DESC | LIMIT 5 | KEEP order_id, brand, product, price"}'
echo ""

echo "--- D. ES|QL vs DSL 对比：同一个问题两种写法 ---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | STATS 销售额 = SUM(amount) BY category | SORT 销售额 DESC"}'
echo ""
echo "########## DONE-L8-7 ##########"

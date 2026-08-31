#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 知识点1：桶聚合 + 指标聚合 ##########"
echo "--- A. 纯指标聚合（不分桶，全量统计）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{
    "总销售额":{"sum":{"field":"amount"}},
    "平均单价":{"avg":{"field":"price"}},
    "最贵":{"max":{"field":"price"}},
    "最便宜":{"min":{"field":"price"}},
    "订单数":{"value_count":{"field":"order_id.keyword"}},
    "去重品牌数":{"cardinality":{"field":"brand.keyword"}},
    "一次返回多个":{"stats":{"field":"price"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
for k,v in a.items():
    if 'value' in v:
        print('   %-12s %s'%(k,v['value']))
    else:
        print('   %-12s count=%s min=%s max=%s avg=%s sum=%s'%(k,v['count'],v['min'],v['max'],round(v['avg'],2),v['sum']))"
echo ""

echo "--- B. 桶聚合 + 子指标（每个品牌：订单数、总销售额、平均单价）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{
    "terms":{"field":"brand.keyword","size":10},
    "aggs":{
      "订单数":{"value_count":{"field":"order_id.keyword"}},
      "总销售额":{"sum":{"field":"amount"}},
      "平均单价":{"avg":{"field":"price"}},
      "最贵商品":{"max":{"field":"price"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   %-6s %-6s %-10s %-10s %-10s'%('品牌','订单数','总销售额','平均单价','最贵'))
for b in d['aggregations']['by_brand']['buckets']:
    ag=b
    print('   %-6s %-6s %-10s %-10s %-10s'%(b['key'],ag['订单数']['value'],ag['总销售额']['value'],round(ag['平均单价']['value'],2),ag['最贵商品']['value']))"
echo ""

echo "--- C. 手算验证：苹果的 avg(price) ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand.keyword":"苹果"}},
  "aggs":{"avg_price":{"avg":{"field":"price"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   苹果 avg(price) =',d['aggregations']['avg_price']['value'])"
echo ""
$C -X POST "$ES/l8_orders/_search?size=20" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand.keyword":"苹果"}},
  "_source":["price","product"]}' | python -c "
import sys,json
d=json.load(sys.stdin)
ps=[h['_source']['price'] for h in d['hits']['hits']]
print('   苹果各单价格:',sorted(ps))
print('   手算: sum=%s / count=%s = %s'%(sum(ps),len(ps),round(sum(ps)/len(ps),4)))"
echo ""

echo "--- D. 多层级桶：品牌 → 品类 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{
    "terms":{"field":"brand.keyword"},
    "aggs":{"by_category":{
      "terms":{"field":"category.keyword"},
      "aggs":{"销售额":{"sum":{"field":"amount"}}}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['by_brand']['buckets']:
    print('   【%s】共 %s 单'%(b['key'],b['doc_count']))
    for c in b['by_category']['buckets']:
        print('      └ %-6s %s 单  销售额 %s'%(c['key'],c['doc_count'],c['销售额']['value']))"
echo ""
echo "########## DONE-L8-4 ##########"

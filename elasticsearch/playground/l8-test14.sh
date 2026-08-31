#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"
IDX="l8_orders_v2"

echo "=== 问题1 修正：桶内销售额 + 外部算占比 ==="
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{
    "by_brand":{"terms":{"field":"brand","size":10},
      "aggs":{"销售额":{"sum":{"field":"amount"}}}},
    "总销售额":{"sum":{"field":"amount"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
tot=a['总销售额']['value']
print('   总销售额: %s'%tot)
print('   %-6s %-10s %-8s %-8s'%('品牌','销售额','占比','订单数'))
for b in a['by_brand']['buckets']:
    v=b['销售额']['value']
    print('   %-6s %-10s %-8s %-8s'%(b['key'],v,str(round(v/tot*100,1))+'%',b['doc_count']))"
echo ""

echo "=== 用 ES|QL 直接算占比（更简洁）==="
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d "{
  \"query\":\"FROM $IDX | STATS total = SUM(amount) BY brand | SORT total DESC\"}"
echo ""

echo "=== 验证：bucket_script 挂在桶内才有效（算平均客单价）==="
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"},
    "aggs":{
      "销售额":{"sum":{"field":"amount"}},
      "订单数":{"value_count":{"field":"order_id"}},
      "客单价":{"bucket_script":{"buckets_path":{"s":"销售额","c":"订单数"},"script":"params.s / params.c"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   %-6s %-10s %-10s'%('品牌','销售额','客单价'))
for b in d['aggregations']['by_brand']['buckets']:
    print('   %-6s %-10s %-10s'%(b['key'],b['销售额']['value'],round(b['客单价']['value'],2)))"
echo ""
echo "########## DONE-L8-14 ##########"

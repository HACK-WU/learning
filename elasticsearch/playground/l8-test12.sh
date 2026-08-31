#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"
IDX="l8_orders_v2"

echo "########## 综合实战：一张销售分析报表 ##########"
echo ""
echo "=== 问题1：各品牌销售额排行（含占比）==="
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{
    "by_brand":{"terms":{"field":"brand","size":10},
      "aggs":{"销售额":{"sum":{"field":"amount"}}}},
    "总销售额":{"sum":{"field":"amount"}},
    "占比":{"bucket_script":{"buckets_path":{"s":"销售额"},"script":"params.s"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
tot=a['总销售额']['value']
print('   总销售额: %s'%tot)
for b in a['by_brand']['buckets']:
    v=b['销售额']['value']
    print('   %-6s %-10s 占比 %s%%'%(b['key'],v,round(v/tot*100,1)))"
echo ""

echo "=== 问题2：哪个城市客单价最高？==="
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_city":{"terms":{"field":"city","size":10},
    "aggs":{
      "订单数":{"value_count":{"field":"order_id"}},
      "销售额":{"sum":{"field":"amount"}},
      "客单价":{"bucket_script":{"buckets_path":{"s":"销售额","c":"订单数"},"script":"params.s / params.c"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
rows=[(b['key'],b['doc_count'],b['销售额']['value'],b['客单价']['value']) for b in d['aggregations']['by_city']['buckets']]
rows.sort(key=lambda x:-x[3])
print('   %-6s %-6s %-10s %-10s'%('城市','订单数','销售额','客单价'))
for r in rows:
    print('   %-6s %-6s %-10s %-10s'%(r[0],r[1],r[2],round(r[3],2)))"
echo ""

echo "=== 问题3：退款率分析（filters 聚合）==="
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"状态分布":{"filters":{"filters":{
    "已完成":{"term":{"status":"已完成"}},
    "退款":{"term":{"status":"退款"}}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
b=d['aggregations']['状态分布']['buckets']
done=b['已完成']['doc_count']; ref=b['退款']['doc_count']
print('   已完成: %s 单'%done)
print('   退款:   %s 单'%ref)
print('   退款率: %s%%'%(round(ref/(done+ref)*100,1)))"
echo ""

echo "=== 问题4：热门标签 TOP5 ==="
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"热门标签":{"terms":{"field":"tags","size":5}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['热门标签']['buckets']:
    print('   %-8s %s 单'%(b['key'],b['doc_count']))"
echo ""

echo "=== 问题5：用 ES|QL 一句话重做问题1 ==="
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d "{
  \"query\":\"FROM $IDX | STATS cnt = COUNT(*), total = SUM(amount), avg_price = AVG(price) BY brand | SORT total DESC\"}"
echo ""
echo "########## DONE-L8-12 ##########"

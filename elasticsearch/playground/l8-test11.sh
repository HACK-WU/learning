#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 正确方案：reindex 到 brand 为 keyword 的索引 ##########"
$C -X DELETE "$ES/l8_orders_v2" > /dev/null 2>&1
$C -X PUT "$ES/l8_orders_v2" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "order_id":{"type":"keyword"},
    "brand":{"type":"keyword"},
    "category":{"type":"keyword"},
    "product":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart","fields":{"kw":{"type":"keyword","ignore_above":256}}},
    "price":{"type":"double"},
    "qty":{"type":"integer"},
    "amount":{"type":"double"},
    "status":{"type":"keyword"},
    "city":{"type":"keyword"},
    "sale_date":{"type":"date"},
    "tags":{"type":"keyword"}}}}'
echo ""

$C -X POST "$ES/_reindex?refresh=true" -H "Content-Type: application/json" -d '{
  "source":{"index":"l8_orders"},
  "dest":{"index":"l8_orders_v2"}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   reindex:',d.get('created'),'条, 失败',len(d.get('failures',[])))"
echo ""

echo "--- 确认新 mapping：brand 已是 keyword ---"
$C "$ES/l8_orders_v2/_mapping?pretty" | python -c "
import sys,json
d=json.load(sys.stdin)
p=d['l8_orders_v2']['mappings']['properties']
for k in ['brand','category','product','city','status','tags','price','amount']:
    v=p.get(k,{})
    print('   %-10s type=%-8s %s'%(k,v.get('type'),('fields='+str(list(v.get('fields',{}).keys())) if 'fields' in v else '')))"
echo ""

echo "--- 正确方案：对 keyword 品牌聚合，结果不再失真 ---"
$C -X POST "$ES/l8_orders_v2/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   桶数:',len(d['aggregations']['by_brand']['buckets']))
for b in d['aggregations']['by_brand']['buckets']:
    print('     %-6s %s 单'%(b['key'],b['doc_count']))"
echo ""

echo "--- 对比：同一个字段，两种 mapping，两种结果 ---"
echo "   旧索引 l8_orders (brand=text+fielddata):"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('      ',[b['key'] for b in d['aggregations']['by_brand']['buckets']])"
echo "   新索引 l8_orders_v2 (brand=keyword):"
$C -X POST "$ES/l8_orders_v2/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('      ',[b['key'] for b in d['aggregations']['by_brand']['buckets']])"
echo ""
echo "########## DONE-L8-11 ##########"

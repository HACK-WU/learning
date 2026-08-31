#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "===== 修复：重建可复现「text 聚合报错」的演示索引 ====="
echo ""
echo "--- 说明：l8_orders 的 fielddata 在演示中被改成了 true，已无法复现报错 ---"
echo "--- 新建 l8_text_demo（brand 为 text，fielddata 保持默认 false）---"
$C -X DELETE "$ES/l8_text_demo" > /dev/null 2>&1
$C -X PUT "$ES/l8_text_demo" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "order_id":{"type":"keyword"},
    "brand":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart"},
    "category":{"type":"keyword"},
    "amount":{"type":"double"},
    "price":{"type":"double"},
    "city":{"type":"keyword"},
    "sale_date":{"type":"date"}}}}'
echo ""

$C -X POST "$ES/_reindex?refresh=true" -H "Content-Type: application/json" -d '{
  "source":{"index":"l8_orders_v2"},
  "dest":{"index":"l8_text_demo"}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('  reindex:',d.get('created'),'条')"
echo ""

echo "--- 确认 brand 是 text 且 fielddata 未开 ---"
$C "$ES/l8_text_demo/_mapping?pretty" | python -c "
import sys,json
d=json.load(sys.stdin)
b=d['l8_text_demo']['mappings']['properties']['brand']
print('  brand type =',b.get('type'),' fielddata =',b.get('fielddata','(默认false)'))"
echo ""

echo "--- 复现报错（这是讲义 1.9 节读者照做应看到的结果）---"
$C -X POST "$ES/l8_text_demo/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('  报错:',d.get('error',{}).get('reason','(无报错)')[:200])"
echo ""

echo "--- 对照：用 brand.keyword 呢？（text 字段没有 keyword 子字段）---"
$C -X POST "$ES/l8_text_demo/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('  报错:',d.get('error',{}).get('reason','(无报错)')[:200])"
echo ""

echo "--- 开启 fielddata=true 后的失真结果 ---"
$C -X PUT "$ES/l8_text_demo/_mapping" -H "Content-Type: application/json" -d '{
  "properties":{"brand":{"type":"text","fielddata":true}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('  设置:',d.get('acknowledged'))"
$C -X POST "$ES/l8_text_demo/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d: print('  报错:',d['error']['reason'][:150])
else:
    print('  桶:',[(b['key'],b['doc_count']) for b in d['aggregations']['by_brand']['buckets']])"
echo ""
echo "########## DONE-L8-16 ##########"

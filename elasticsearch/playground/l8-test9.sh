#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 聚合 vs 搜索：本质区别 ##########"
echo "--- A. 搜索：返回文档，有 _score，按相关性排序 ---"
$C -X POST "$ES/l8_orders/_search" -H "Content-Type: application/json" -d '{
  "size":3,"query":{"match":{"product":"苹果"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中 %s 条, max_score=%s'%(d['hits']['total']['value'],d['hits']['max_score']))
for h in d['hits']['hits']:
    print('     score=%s  %s'%(round(h['_score'],4),h['_source']['product']))"
echo ""

echo "--- B. 聚合：返回统计值，size=0，无 _score ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"match":{"product":"苹果"}},
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   hits 数组长度:',len(d['hits']['hits']),'（size=0 所以没文档）')
print('   聚合结果:')
for b in d['aggregations']['by_brand']['buckets']:
    print('     %-6s %s 单'%(b['key'],b['doc_count']))"
echo ""

echo "--- C. query 限定范围 + aggs 统计（两者协作）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"term":{"status.keyword":"已完成"}},
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword"},
    "aggs":{"销售额":{"sum":{"field":"amount"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   已完成订单的品牌销售额:')
for b in d['aggregations']['by_brand']['buckets']:
    print('     %-6s %s 单  %s'%(b['key'],b['doc_count'],b['销售额']['value']))"
echo ""

echo "--- D. cardinality 是近似值（precision_threshold）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"低精度":{"cardinality":{"field":"order_id.keyword","precision_threshold":100}},
    "count_exact":{"value_count":{"field":"order_id.keyword"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
print('   cardinality(去重) =',a['低精度']['value'])
print('   value_count(不去重) =',a['count_exact']['value'])"
echo ""

echo "--- E. terms 聚合的 doc_count_error_upper_bound（近似性）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword","size":2}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']['by_brand']
print('   sum_other_doc_count =',a.get('sum_other_doc_count'))
print('   doc_count_error_upper_bound =',a.get('doc_count_error_upper_bound'))
print('   返回的桶:',[(b['key'],b['doc_count']) for b in a['buckets']])"
echo ""

echo "--- F. 单分片下的精确性说明 ---"
$C "$ES/l8_orders/_settings?pretty" | python -c "
import sys,json
d=json.load(sys.stdin)
s=d['l8_orders']['settings']['index']
print('   number_of_shards =',s.get('number_of_shards'))
print('   number_of_replicas =',s.get('number_of_replicas'))"
echo ""
echo "########## DONE-L8-9 ##########"

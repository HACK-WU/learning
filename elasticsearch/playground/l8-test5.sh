#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 知识点2：子聚合 + 管道聚合 ##########"
echo "--- A. 管道聚合：找出销售额最高的品牌（max_bucket）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{
    "by_brand":{"terms":{"field":"brand.keyword"},
      "aggs":{"销售额":{"sum":{"field":"amount"}}}},
    "销售额最高的品牌":{"max_bucket":{"buckets_path":"by_brand>销售额"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
mb=d['aggregations']['销售额最高的品牌']
print('   max_bucket → keys=%s value=%s'%(mb.get('keys'),mb.get('value')))"
echo ""

echo "--- B. 管道聚合：累计求和（cumulative_sum）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword","order":{"_key":"asc"}},
    "aggs":{
      "销售额":{"sum":{"field":"amount"}},
      "累计":{"cumulative_sum":{"buckets_path":"销售额"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['by_brand']['buckets']:
    print('   %-6s 销售额=%-10s 累计=%s'%(b['key'],b['销售额']['value'],b['累计']['value']))"
echo ""

echo "--- C. 管道聚合：派生指标（bucket_script 算平均客单价）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand.keyword"},
    "aggs":{
      "销售额":{"sum":{"field":"amount"}},
      "订单数":{"value_count":{"field":"order_id.keyword"}},
      "平均客单价":{"bucket_script":{"buckets_path":{"s":"销售额","c":"订单数"},"script":"params.s / params.c"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['by_brand']['buckets']:
    print('   %-6s 平均客单价=%s'%(b['key'],round(b['平均客单价']['value'],2)))"
echo ""

echo "--- D. date_histogram：按周看销售趋势 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_week":{"date_histogram":{"field":"sale_date","calendar_interval":"week"},
    "aggs":{"销售额":{"sum":{"field":"amount"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
bs=d['aggregations']['by_week']['buckets']
print('   共 %s 个桶'%len(bs))
for b in bs:
    print('   %s  %s 单  销售额 %s'%(b['key_as_string'][:10],b['doc_count'],b['销售额']['value']))"
echo ""

echo "--- E. range 分桶：价格区间分布 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"price_range":{"range":{"field":"price","ranges":[
    {"to":3000},{"from":3000,"to":6000},{"from":6000,"to":10000},{"from":10000}]}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['price_range']['buckets']:
    k=b.get('key')
    print('   %-14s %s 单'%(k,b['doc_count']))"
echo ""

echo "--- F. filter 聚合：只统计已完成订单 ---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"已完成的":{"filter":{"term":{"status.keyword":"已完成"}},
    "aggs":{"销售额":{"sum":{"field":"amount"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']['已完成的']
print('   已完成订单: %s 单, 销售额 %s'%(a['doc_count'],a['销售额']['value']))"
echo ""
echo "########## DONE-L8-5 ##########"

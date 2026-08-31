#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 补测：有效的搜索 vs 聚合对比 ##########"
echo "--- A. 搜 product 含「iPhone」（能命中）---"
$C -X POST "$ES/l8_orders/_search" -H "Content-Type: application/json" -d '{
  "size":3,"query":{"match":{"product":"iPhone"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中 %s 条, max_score=%s'%(d['hits']['total']['value'],round(d['hits']['max_score'],4)))
for h in d['hits']['hits']:
    print('     score=%s  %s'%(round(h['_score'],4),h['_source']['product']))"
echo ""

echo "--- B. 同一 query 下做聚合（query 定范围 + aggs 做统计）---"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"match":{"product":"iPhone"}},
  "aggs":{"均价":{"avg":{"field":"price"}},"总额":{"sum":{"field":"amount"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
print('   命中但 size=0，hits 长度:',len(d['hits']['hits']))
print('   聚合 → 均价=%s  总额=%s'%(a['均价']['value'],a['总额']['value']))"
echo ""

echo "--- C. 为什么搜「苹果」在 product 里命中 0 条？看分词 ---"
$C -X POST "$ES/l8_orders/_analyze" -H "Content-Type: application/json" -d '{
  "field":"product","text":"iPhone 15 Pro"}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   iPhone 15 Pro →',[t['token'] for t in d['tokens']])"
$C -X POST "$ES/l8_orders/_analyze" -H "Content-Type: application/json" -d '{
  "field":"brand_text","text":"苹果"}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   苹果 →',[t['token'] for t in d['tokens']])"
echo ""

echo "--- D. 口径确认：搜 brand_text 能命中苹果 ---"
$C -X POST "$ES/l8_orders/_search" -H "Content-Type: application/json" -d '{
  "size":2,"query":{"match":{"brand_text":"苹果"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中 %s 条'%(d['hits']['total']['value']))
for h in d['hits']['hits']:
    print('     score=%s  %s %s'%(round(h['_score'],4),h['_source']['brand'],h['_source']['product']))"
echo ""

echo "--- E. 修复演示：把 brand 改回纯 keyword（对比 fielddata 方案）---"
echo "    E1. fielddata=true 方案（不推荐，吃内存）"
$C -X PUT "$ES/l8_orders/_mapping" -H "Content-Type: application/json" -d '{
  "properties":{"brand":{"type":"text","fielddata":true}}}'
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d: print('     报错:',d['error']['reason'][:80])
else:
    for b in d['aggregations']['by_brand']['buckets']:
        print('     %-6s %s 单'%(b['key'],b['doc_count']))"
echo ""
echo "########## DONE-L8-10 ##########"

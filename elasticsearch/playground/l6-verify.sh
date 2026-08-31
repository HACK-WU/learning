#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

show() {
python -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d:
    print('   ERROR:', d['error'].get('reason','')[:200]); sys.exit()
print('   命中:',d['hits']['total']['value'],'条  max_score=',d['hits']['max_score'])
for h in d['hits']['hits']:
    print('     %s  %s'%(round(h['_score'],4) if h['_score'] is not None else 'None',h['_source'].get('name')))"
}

echo "########## 补测 1：exists 查询（速查表里列了，需验证）##########"
echo "--- 有 brand 字段的（应 8 条）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"exists":{"field":"brand"}}}' | show
echo ""
echo "--- 有 tags 字段的（应 8 条）---"
$C -X POST "$ES/l6_shop/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"exists":{"field":"tags"}}}'
echo ""
echo "--- 有个不存在的字段 missing_field（应 0 条）---"
$C -X POST "$ES/l6_shop/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"exists":{"field":"missing_field"}}}'
echo ""

echo "########## 补测 2：multi_match（速查表里列了，需验证）##########"
echo "--- 同时在 name 和 brand 里搜「苹果」---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"multi_match":{"query":"苹果","fields":["name","brand"]}}}' | show
echo ""
echo "--- multi_match best_fields（默认）vs cross_fields ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"multi_match":{"query":"苹果","fields":["name","brand"],"type":"best_fields"}}}' | show
echo ""

echo "########## 补测 3：验证课6第一幕的 term 0条原文 ##########"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name":"苹果手机"}}}'
echo ""
echo "########## 补测 4：验证 match 6条原文 ##########"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":"苹果手机"}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  max_score=',d['hits']['max_score'])
for h in d['hits']['hits']: print('     %s  %s'%(round(h['_score'],4),h['_source']['name']))"
echo ""
echo "########## 补测 5：验证 0.9894（苹果单词在iPhone的分数，SVG里用了）##########"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name":"苹果"}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('     %s  %s'%(round(h['_score'],4),h['_source']['name']))"
echo ""
echo "########## 补测 6：验证「手机」单词在各文档的分数 ##########"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name":"手机"}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('     %s  %s'%(round(h['_score'],4),h['_source']['name']))"
echo ""
echo "########## DONE-9 ##########"

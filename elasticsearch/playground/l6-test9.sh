#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 19-B. 完整 DSL 骨架（修复 sort=None 问题）##########"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "from":0,
  "size":3,
  "_source":["name","price","brand"],
  "sort":[{"price":{"order":"desc"}}],
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "filter":[{"range":{"price":{"gte":1000}}}],
    "must_not":[{"term":{"brand":"Apple"}}],
    "should":[{"term":{"tags":"旗舰"}}],
    "minimum_should_match":0}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  max_score=',d['hits']['max_score'])
for h in d['hits']['hits']:
    s=h.get('sort')
    print('    score=%s  %s | %s | sort=%s'%(round(h['_score'],4) if h['_score'] is not None else 'None',
        h['_source']['name'], h['_source']['price'], s))"
echo ""

echo "########## 21. 对照：去掉 sort 看分数 ##########"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":5,
  "_source":["name","price","brand","tags"],
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "filter":[{"range":{"price":{"gte":1000}}}],
    "must_not":[{"term":{"brand":"Apple"}}],
    "should":[{"term":{"tags":"旗舰"}}],
    "minimum_should_match":0}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']:
    print('    score=%s  %s | %s | %s'%(round(h['_score'],4),
        h['_source']['name'], h['_source']['price'], h['_source']['tags']))"
echo ""

echo "########## 22. 同一个 should，minimum_should_match 0 vs 1 的分数差 ##########"
echo "[minimum_should_match=0 → should 只加分不筛选]"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "should":[{"term":{"tags":"旗舰"}}],
    "minimum_should_match":0}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('     %s  %s  tags=%s'%(round(h['_score'],4),h['_source']['name'],h['_source']['tags']))"
echo ""
echo "[minimum_should_match=1 → should 变成硬性条件]"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "should":[{"term":{"tags":"旗舰"}}],
    "minimum_should_match":1}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('     %s  %s  tags=%s'%(round(h['_score'],4),h['_source']['name'],h['_source']['tags']))"
echo ""

echo "########## 23. 最终确认：filter 是否真的影响相关性排序 ##########"
echo "[对照] 搜「手机」不加任何 filter:"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":"手机"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('     %s  %s'%(round(h['_score'],4),h['_source']['name']))"
echo ""
echo "[实验] 搜「手机」+ filter(stock>=20) —— 若 filter 不影响打分，命中项的分数应逐一不变:"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "filter":[{"range":{"stock":{"gte":20}}}]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('     %s  %s (stock=%s)'%(round(h['_score'],4),h['_source']['name'],h['_source']['stock']))"
echo ""
echo "########## DONE-8 ##########"

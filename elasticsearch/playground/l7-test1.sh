#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== 环境检查 ==="
$C "$ES?filter_path=version.number" 
echo ""
echo "--- 现有索引 ---"
$C "$ES/_cat/indices?v"
echo ""

echo "########## 0. 建课7专用索引 l7_news（为讲 BM25 设计：词频+长度差异明显）##########"
$C -X DELETE "$ES/l7_news" > /dev/null 2>&1
$C -X PUT "$ES/l7_news" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "title":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart"},
    "content":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart"},
    "author":{"type":"keyword"},
    "category":{"type":"keyword"},
    "views":{"type":"integer"},
    "publish_date":{"type":"date"},
    "is_top":{"type":"boolean"}}}}'
echo ""

echo "--- 写入 6 篇文章（设计要点见注释）---"
$C -X POST "$ES/l7_news/_bulk?refresh=true" -H "Content-Type: application/json" -d '
{"index":{"_id":"1"}}
{"title":"苹果发布 iPhone 15","content":"苹果公司今天发布了 iPhone 15 手机，苹果 CEO 表示这是最好的苹果手机。苹果手机销量创新高。","author":"张三","category":"科技","views":5000,"publish_date":"2026-08-01","is_top":false}
{"index":{"_id":"2"}}
{"title":"华为发布 Mate 60","content":"华为公司今天发布了 Mate 60 手机，搭载自研芯片。","author":"李四","category":"科技","views":8000,"publish_date":"2026-08-05","is_top":true}
{"index":{"_id":"3"}}
{"title":"小米发布 SU7 汽车","content":"小米公司今天发布了 SU7 汽车，雷军表示这是小米的转折点。","author":"王五","category":"汽车","views":12000,"publish_date":"2026-08-10","is_top":false}
{"index":{"_id":"4"}}
{"title":"苹果股价上涨","content":"苹果公司股价今日上涨，分析师看好苹果前景。苹果的市值创新高。","author":"张三","category":"财经","views":3000,"publish_date":"2026-08-15","is_top":false}
{"index":{"_id":"5"}}
{"title":"手机市场分析报告","content":"2026年手机市场分析：苹果手机、华为手机、小米手机三家占据主要份额。手机行业竞争激烈。","author":"赵六","category":"科技","views":20000,"publish_date":"2026-08-20","is_top":false}
{"index":{"_id":"6"}}
{"title":"苹果手机降价促销","content":"苹果手机今日降价，苹果官方称苹果手机促销力度空前。","author":"钱七","category":"科技","views":6000,"publish_date":"2026-08-25","is_top":false}
'
echo ""
echo "--- 确认 6 条 ---"
$C "$ES/l7_news/_count"
echo ""

echo "########## 1. 复现课6的悬念：为什么「小米14手机」分数比「苹果iPhone15Pro」高？##########"
echo "--- 用 l6_shop 搜「手机」看分数 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":"手机"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'])
for h in d['hits']['hits']:
    print('     %s  %s'%(round(h['_score'],4),h['_source']['name']))"
echo ""

echo "########## 2. BM25 三要素实验：词频 TF ##########"
echo "--- 搜「苹果」，观察词频对分数的影响 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"苹果"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  max_score=',round(d['hits']['max_score'],4))
for h in d['hits']['hits']:
    print('     %s  doc%s  %s'%(round(h['_score'],4),h['_id'],h['_source']['title']))"
echo ""

echo "--- 用 explain 看 doc1（苹果出现4次）的算分明细 ---"
$C -X POST "$ES/l7_news/_explain/1" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"苹果"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
def walk(exp,depth=0):
    pad='  '*(depth+3)
    print(f\"{pad}{exp.get('description')}  →  {round(exp.get('value',0),4)}\")
    for c in exp.get('details',[]):
        walk(c,depth+1)
walk(d.get('explanation',{}))"
echo ""

echo "--- 对比 doc4（苹果出现3次）的算分明细 ---"
$C -X POST "$ES/l7_news/_explain/4" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"苹果"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
def walk(exp,depth=0):
    pad='  '*(depth+3)
    print(f\"{pad}{exp.get('description')}  →  {round(exp.get('value',0),4)}\")
    for c in exp.get('details',[]):
        walk(c,depth+1)
walk(d.get('explanation',{}))"
echo ""
echo "########## DONE-L7-1 ##########"

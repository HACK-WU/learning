#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 10. 高亮 highlighting ##########"
echo "--- 基础高亮 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"苹果"}},
  "highlight":{"fields":{"content":{}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for h in d['hits']['hits']:
    print('   doc%s  %s'%(h['_id'],h['_source']['title']))
    for frag in h.get('highlight',{}).get('content',[]):
        print('      →',frag.replace(chr(10),' '))"
echo ""

echo "--- 自定义高亮标签 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"苹果"}},
  "highlight":{
    "pre_tags":["<mark>"],"post_tags":["</mark>"],
    "fields":{"content":{"fragment_size":50,"number_of_fragments":2}}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
for h in d['hits']['hits'][:2]:
    print('   doc%s:'%h['_id'])
    for frag in h.get('highlight',{}).get('content',[]):
        print('      →',frag.replace(chr(10),' '))"
echo ""

echo "--- 高亮 title 和 content 两个字段 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"multi_match":{"query":"苹果","fields":["title","content"]}},
  "highlight":{
    "pre_tags":["【"],"post_tags":["】"],
    "fields":{"title":{},"content":{}}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
for h in d['hits']['hits'][:3]:
    hl=h.get('highlight',{})
    print('   doc%s  title_hl=%s'%(h['_id'],hl.get('title',[])))
    print('        content_hl=%s'%(str(hl.get('content',[]))[:120]))"
echo ""

echo "########## 11. 相关性调优：boost 字段权重 ##########"
echo "--- 基准：multi_match 不给权重 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"multi_match":{"query":"苹果","fields":["title","content"]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'])
for h in d['hits']['hits']: print('     %s  doc%s %s'%(round(h['_score'],4),h['_id'],h['_source']['title']))"
echo ""

echo "--- title 权重提高 3 倍（title^3）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"multi_match":{"query":"苹果","fields":["title^3","content"]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'])
for h in d['hits']['hits']: print('     %s  doc%s %s'%(round(h['_score'],4),h['_id'],h['_source']['title']))"
echo ""

echo "--- 用 explain 看 title^3 的 boost 生效 ---"
$C -X POST "$ES/l7_news/_explain/6" -H "Content-Type: application/json" -d '{
  "query":{"multi_match":{"query":"苹果","fields":["title^3","content"]}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
def walk(exp,depth=0):
    pad='  '*(depth+2)
    v=exp.get('value'); vs=round(v,4) if isinstance(v,(int,float)) else v
    print(f\"{pad}{exp.get('description')}  →  {vs}\")
    for c in exp.get('details',[]): walk(c,depth+1)
walk(d['explanation'])"
echo ""

echo "########## 12. boosting query：降低某些文档的分数 ##########"
echo "--- 把 category=财经 的文章降权（negative_boost=0.2）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"boosting":{
    "positive":{"match":{"content":"苹果"}},
    "negative":{"term":{"category":"财经"}},
    "negative_boost":0.2}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'])
for h in d['hits']['hits']: print('     %s  doc%s %s [%s]'%(round(h['_score'],4),h['_id'],h['_source']['title'],h['_source']['category']))"
echo ""
echo "--- 对照：不加降权 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"苹果"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('     %s  doc%s %s [%s]'%(round(h['_score'],4),h['_id'],h['_source']['title'],h['_source']['category']))"
echo ""

echo "########## 13. function_score：按浏览量加权 ##########"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"function_score":{
    "query":{"match":{"content":"苹果"}},
    "field_value_factor":{"field":"views","modifier":"log1p","factor":0.5},
    "boost_mode":"multiply"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'])
for h in d['hits']['hits']: print('     %s  doc%s %s views=%s'%(round(h['_score'],4),h['_id'],h['_source']['title'],h['_source']['views']))"
echo ""

echo "########## 14. fuzziness 容错 ##########"
echo "--- 正确拼写 iPhone ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"iPhone"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('     %s  doc%s'%(round(h['_score'],4),h['_id']))"
echo ""
echo "--- 错误拼写 IPhone（不加 fuzziness）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"Iphane"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')"
echo ""
echo "--- 加 fuzziness:auto ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":{"query":"Iphane","fuzziness":"auto"}}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('     %s  doc%s %s'%(round(h['_score'],4),h['_id'],h['_source']['title']))"
echo ""
echo "########## DONE-L7-4 ##########"

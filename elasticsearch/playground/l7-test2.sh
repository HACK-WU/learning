#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

explain() {
python -c "
import sys,json
d=json.load(sys.stdin)
if 'explanation' not in d:
    print('   无 explain:',json.dumps(d,ensure_ascii=False)[:200]); sys.exit()
def walk(exp,depth=0):
    pad='  '*(depth+2)
    v=exp.get('value')
    vs=round(v,4) if isinstance(v,(int,float)) else v
    print(f\"{pad}{exp.get('description')}  →  {vs}\")
    for c in exp.get('details',[]):
        walk(c,depth+1)
walk(d['explanation'])"
}

echo "########## 3. 手算验证 BM25 公式 ##########"
python -c "
import math
print('=== doc1: boost * idf * tf ===')
boost=2.2; k1=1.2; b=0.75
N=6; n=4
idf=math.log(1+(N-n+0.5)/(n+0.5))
print(f'  idf = log(1 + (6-4+0.5)/(4+0.5)) = log(1+{2.5/4.5:.6f}) = {idf:.6f}')
freq=4.0; dl=23.0; avgdl=17.5
tf=freq/(freq+k1*(1-b+b*dl/avgdl))
print(f'  tf  = 4 / (4 + 1.2*(1-0.75+0.75*23/17.5)) = {tf:.6f}')
print(f'  score = {boost} * {idf:.6f} * {tf:.6f} = {boost*idf*tf:.6f}')
print()
print('=== doc4: boost * idf * tf ===')
freq=3.0; dl=18.0
tf4=freq/(freq+k1*(1-b+b*dl/avgdl))
print(f'  tf  = 3 / (3 + 1.2*(1-0.75+0.75*18/17.5)) = {tf4:.6f}')
print(f'  score = {boost} * {idf:.6f} * {tf4:.6f} = {boost*idf*tf4:.6f}')
print()
print('=== doc6 (freq=3, dl=15) ===')
freq=3.0; dl=15.0
tf6=freq/(freq+k1*(1-b+b*dl/avgdl))
print(f'  tf  = 3 / (3 + 1.2*(1-0.75+0.75*15/17.5)) = {tf6:.6f}')
print(f'  score = {boost} * {idf:.6f} * {tf6:.6f} = {boost*idf*tf6:.6f}')
"
echo ""

echo "########## 4. IDF 实验：罕见词 vs 常见词 ##########"
echo "--- 搜罕见词「雷军」（只在 doc3 出现）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"雷军"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  max_score=',round(d['hits']['max_score'],4))
for h in d['hits']['hits']: print('     %s  doc%s %s'%(round(h['_score'],4),h['_id'],h['_source']['title']))"
echo ""
$C -X POST "$ES/l7_news/_explain/3" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"雷军"}}}' | explain
echo ""

echo "--- 搜常见词「手机」（在多篇出现）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"手机"}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  max_score=',round(d['hits']['max_score'],4))
for h in d['hits']['hits']: print('     %s  doc%s %s'%(round(h['_score'],4),h['_id'],h['_source']['title']))"
echo ""
$C -X POST "$ES/l7_news/_explain/5" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"手机"}}}' | explain
echo ""

echo "--- 计算两个词的 idf 对比 ---"
python -c "
import math
for term,n in [('雷军',1),('手机',4),('苹果',4)]:
    N=6
    idf=math.log(1+(N-n+0.5)/(n+0.5))
    print(f'  {term}: n={n}, idf = log(1 + (6-{n}+0.5)/({n}+0.5)) = {idf:.4f}')
"
echo ""

echo "########## 5. 字段长度归一化实验 ##########"
echo "--- 同一个词在不同长度字段中的 tf ---"
$C -X POST "$ES/l7_news/_explain/6" -H "Content-Type: application/json" -d '{
  "query":{"match":{"content":"苹果"}}}' | explain
echo ""
echo "--- 各文档 content 字段长度 dl ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":6,"_source":["title"],
  "script_fields":{
    "dl":{"script":{"source":"doc[\"content\"].size()"}}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
print('   doc  title                    dl(词项数)')
for h in d['hits']['hits']:
    print('   %-4s %-24s %s'%(h['_id'],h['_source']['title'],h['fields']['dl'][0]))"
echo ""
echo "########## DONE-L7-2 ##########"

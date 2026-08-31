#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 12-B. profile 验证 query vs filter 执行差异（原始输出）##########"

echo "=== query 上下文（term 直接写在 query 下）==="
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,"profile":true,
  "query":{"term":{"brand":"Apple"}}}' > /tmp/q.json 2>&1
python -c "
import json
d=json.load(open('/tmp/q.json'))
if 'error' in d: print('  ERROR:',json.dumps(d['error'],ensure_ascii=False)[:400])
else:
    for sh in d.get('profile',{}).get('shards',[]):
        for q in sh.get('query',[]):
            print('  type:',q.get('type'))
            print('  desc:',q.get('description'))
            print('  time:',q.get('time_in_nanos'),'ns')
            for c in q.get('children',[]):
                print('    - child:',c.get('type'),'|',c.get('time_in_nanos'),'ns |',c.get('description'))
"
echo ""

echo "=== filter 上下文（term 包在 bool.filter 里）==="
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,"profile":true,
  "query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' > /tmp/f.json 2>&1
python -c "
import json
d=json.load(open('/tmp/f.json'))
if 'error' in d: print('  ERROR:',json.dumps(d['error'],ensure_ascii=False)[:400])
else:
    for sh in d.get('profile',{}).get('shards',[]):
        for q in sh.get('query',[]):
            print('  type:',q.get('type'))
            print('  desc:',q.get('description'))
            print('  time:',q.get('time_in_nanos'),'ns')
            for c in q.get('children',[]):
                print('    - child:',c.get('type'),'|',c.get('time_in_nanos'),'ns |',c.get('description'))
"
echo ""

echo "########## 15. 补充：should 单独使用时的默认行为 ##########"
echo "--- 只有 should（无 must/filter）→ 默认 minimum_should_match=1 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"should":[
    {"term":{"brand":"Apple"}},
    {"term":{"brand":"Lenovo"}}]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('      ',h['_source']['brand'],'|',h['_source']['name'])"
echo ""

echo "--- 显式 minimum_should_match=2（两个都要满足 → 0条，因为 brand 是单值）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"should":[
    {"term":{"brand":"Apple"}},
    {"term":{"brand":"Lenovo"}}],
    "minimum_should_match":2}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  ← 单值字段无法同时等于两个值')"
echo ""

echo "########## 16. 补充：must_not 不能单独用 ##########"
echo "--- 只有 must_not（无条件排除）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"must_not":[{"term":{"brand":"Apple"}}]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  max_score=',d['hits']['max_score'])
print('   （match_all - Apple = 8-3 = 5 条，score 全 0）')"
echo ""

echo "--- must_not + filter 组合（先圈定再排除）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "filter":[{"range":{"price":{"gte":1000}}}],
    "must_not":[{"term":{"brand":"Apple"}}]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('      ',h['_source']['name'],h['_source']['price'])"
echo ""

echo "########## 17. 补充：nested bool 与 score 叠加 ##########"
echo "--- should 内再加 bool，观察分数累加 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"should":[
    {"match":{"name":"苹果"}},
    {"match":{"name":"手机"}},
    {"term":{"brand":"Huawei"}}]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print(f\"      {h['_score']:.4f}  {h['_source']['name']}\")"
echo ""
echo "########## DONE-5 ##########"

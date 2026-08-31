#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 11. DSL 结构：_source 过滤 / 分页 / 排序 ##########"

echo "--- A. 只要部分字段（_source filtering）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "_source":["name","price"],
  "query":{"term":{"brand":"Apple"}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('   ',h['_source'])"
echo ""

echo "--- B. 分页 from/size ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "from":0,"size":2,"query":{"match_all":{}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('   第1页:',[h['_id'] for h in d['hits']['hits']])"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "from":2,"size":2,"query":{"match_all":{}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('   第2页:',[h['_id'] for h in d['hits']['hits']])"
echo ""

echo "--- C. 排序 sort（keyword 字段）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":3,"sort":[{"price":{"order":"desc"}}],"query":{"match_all":{}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   sort 字段:',d['hits']['hits'][0].get('sort'))
for h in d['hits']['hits']: print(f\"    {h['_source']['name']} {h['_source']['price']}\")"
echo ""

echo "########## 12. filter 缓存：用 _cache 统计验证 ##########"
echo "--- 清空缓存后第一次 filter 查询 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,"query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' > /dev/null
echo "--- 用 profile 看 query 执行细节 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,"profile":true,
  "query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
def walk(shards):
    for sh in shards:
        for q in sh.get('query',[]):
            print('   query type:',q.get('type'),'| time:',q.get('time_in_nanos'),'ns | desc:',q.get('description'))
            for c in q.get('children',[]):
                print('      child:',c.get('type'),'| time:',c.get('time_in_nanos'),'ns |',c.get('description'))
walk(d.get('profile',{}).get('shards',[]))"
echo ""

echo "--- 对比：query 上下文的同样条件（走打分）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,"profile":true,
  "query":{"term":{"brand":"Apple"}}}' \
| python -c "
import sys,json
d=json.load(sys.stdin)
for sh in d.get('profile',{}).get('shards',[]):
    for q in sh.get('query',[]):
        print('   query type:',q.get('type'),'| time:',q.get('time_in_nanos'),'ns |',q.get('description'))
        for c in q.get('children',[]):
            print('      child:',c.get('type'),'| time:',c.get('time_in_nanos'),'ns |',c.get('description'))"
echo ""

echo "########## 13. 翻车演示：term 查 text 字段的常见错误 ##########"
echo "--- 错误：用 term 查 name 的完整句子 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name":"苹果 iPhone 15 Pro 手机"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  ← 为什么是0？因为 name 是 text，索引里没有这个完整词项')"
echo ""

echo "--- 正确：改用 match ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":"苹果 iPhone 15 Pro 手机"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条  max_score=%.4f'%d['hits']['max_score'])
for h in d['hits']['hits'][:3]: print(f\"      {h['_score']:.4f} {h['_source']['name']}\")"
echo ""

echo "--- 正确：或用 name.raw 精确匹配 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name.raw":"苹果 iPhone 15 Pro 手机"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print(f\"      {h['_score']:.4f} {h['_source']['name']}\")"
echo ""

echo "########## 14. 验证：match 查 keyword 字段 vs term 查 keyword ##########"
echo "--- match 查 tags（keyword 数组）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"tags":"旗舰"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('      ',h['_source']['name'],h['_source']['tags'])"
echo ""

echo "--- terms 查多值（任一命中即可）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"terms":{"brand":["Apple","Huawei"]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']: print('      ',h['_source']['name'],'|',h['_source']['brand'])"
echo ""

echo "########## DONE-4 ##########"

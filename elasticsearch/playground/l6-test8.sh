#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 18. 尝试用 node stats 观察 query_cache ##########"
echo "--- 先记一次基线 ---"
$C "$ES/_nodes/stats/indices/query_cache?filter_path=**.query_cache" \
 | python -c "
import sys,json
d=json.load(sys.stdin)
for k,v in d.get('nodes',{}).items():
    qc=v.get('indices',{}).get('query_cache',{})
    print('  hit_count=%s miss_count=%s cache_size=%s'%(qc.get('hit_count'),qc.get('miss_count'),qc.get('cache_size')))"
echo ""

echo "--- 执行 5 次相同的 filter 查询 ---"
for i in 1 2 3 4 5; do
  $C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
    "size":0,"query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' > /dev/null
done

echo "--- 再看 query_cache ---"
$C "$ES/_nodes/stats/indices/query_cache?filter_path=**.query_cache" \
 | python -c "
import sys,json
d=json.load(sys.stdin)
for k,v in d.get('nodes',{}).items():
    qc=v.get('indices',{}).get('query_cache',{})
    print('  hit_count=%s miss_count=%s cache_size=%s'%(qc.get('hit_count'),qc.get('miss_count'),qc.get('cache_size')))"
echo ""

echo "--- 结论：8 条文档量级太小，缓存效果不可测 ---"
echo ""

echo "########## 19. DSL 基础结构验证 ##########"
echo "--- match_all ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match_all":{}}}' \
| python -c "import sys,json;d=json.load(sys.stdin);print('   命中:',d['hits']['total']['value'],'条, max_score=',d['hits']['max_score'])"
echo ""

echo "--- match_all + boost ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match_all":{"boost":2.0}}}' \
| python -c "import sys,json;d=json.load(sys.stdin);print('   max_score=',d['hits']['max_score'])"
echo ""

echo "--- 完整 DSL 骨架（各部件齐活）---"
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
print('   命中:',d['hits']['total']['value'],'条')
for h in d['hits']['hits']:
    print(f\"     {h['_score']:.4f} {h['_source']['name']} | {h['_source']['price']} | sort={h.get('sort')}\")"
echo ""

echo "########## 20. 验证 query 与 filter 的分数差异（决定性证据）##########"
echo "--- 场景：搜「手机」，条件是 brand=Apple ---"
echo ""
echo "[A] brand 放 must（参与打分）:"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"must":[{"match":{"name":"手机"}},{"term":{"brand":"Apple"}}]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print(f\"     score={h['_score']:.4f}  {h['_source']['name']}\")"
echo ""
echo "[B] brand 放 filter（不打分）:"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"must":[{"match":{"name":"手机"}}],"filter":[{"term":{"brand":"Apple"}}]}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print(f\"     score={h['_score']:.4f}  {h['_source']['name']}\")"
echo ""
echo "[C] 无任何 brand 条件（对照组）:"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":"手机"}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print(f\"     score={h['_score']:.4f}  {h['_source']['name']}\")"
echo ""
echo "########## DONE-7 ##########"

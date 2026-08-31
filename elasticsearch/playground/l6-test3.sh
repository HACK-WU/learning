#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

show() {
python -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d:
    print('  ERROR:', d['error'].get('reason','')[:250]); sys.exit()
t=d['hits']['total']['value']
print(f'  命中 {t} 条  max_score={d[\"hits\"][\"max_score\"]}')
for h in d['hits']['hits']:
    print(f\"    {h['_score']:.4f}  {h['_source']['name']}  [品牌:{h['_source']['brand']} 价格:{h['_source']['price']}]\")"
}

echo "########## 5. bool 四大子句 ##########"

echo "--- A. must：必须满足，参与打分 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"must":[{"match":{"name":"手机"}}]}}}' | show
echo ""

echo "--- B. should：应该满足，满足则加分（只写 should 时至少满足1个）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"should":[{"term":{"brand":"Apple"}},{"term":{"brand":"Xiaomi"}}]}}}' | show
echo ""

echo "--- C. must_not：必须不满足，不打分（filter 上下文）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"must_not":[{"term":{"brand":"Apple"}}]}}}' | show
echo ""

echo "--- D. filter：必须满足，但不打分 + 可缓存 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' | show
echo ""

echo "########## 6. 组合实战：must + filter（打分与筛选分离）##########"
echo "--- 搜「手机」，但只看有货的（stock>0）且品牌是 Apple ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "filter":[{"term":{"brand":"Apple"}},{"range":{"stock":{"gt":0}}}]}}}' | show
echo ""

echo "--- 同样条件，但把品牌条件放进 must（参与打分，score 不同）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}},{"term":{"brand":"Apple"}}]}}}' | show
echo ""

echo "########## 7. 关键验证：filter 到底影不影响打分？##########"
echo "--- 只 must（match 手机）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":"手机"}}}' | show
echo ""

echo "--- must(手机) + filter(stock>0) —— 分数应与上面完全一致 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "filter":[{"range":{"stock":{"gt":0}}}]}}}' | show
echo ""

echo "########## 8. minimum_should_match 在 bool 中的行为 ##########"
echo "--- must + should 并存时，should 默认可一个都不满足（minimum_should_match=0）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "should":[{"term":{"brand":"Apple"}}]}}}' | show
echo ""

echo "--- 显式设 minimum_should_match=1（should 至少满足1个）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"bool":{
    "must":[{"match":{"name":"手机"}}],
    "should":[{"term":{"brand":"Apple"}}],
    "minimum_should_match":1}}}' | show
echo ""

echo "########## 9. range 查询（数值与日期）##########"
echo "--- 价格 1000-5000 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"range":{"price":{"gte":1000,"lte":5000}}}}' | show
echo ""

echo "--- 2026-08-01 之后上架 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"range":{"created_at":{"gte":"2026-08-01"}}}}' | show
echo ""

echo "########## 10. 验证 filter 缓存：看查询耗时 ##########"
echo "--- 连续 3 次 filter 查询，观察 took ---"
for i in 1 2 3; do
  $C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
    "query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' \
  | python -c "
import sys,json;d=json.load(sys.stdin)
print(f\"  第${i}次: took={d['took']}ms\")"
done
echo ""
echo "########## DONE-3 ##########"

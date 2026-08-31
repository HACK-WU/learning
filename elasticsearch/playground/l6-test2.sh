#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

show() {
python -c "
import sys,json
try:
    d=json.load(sys.stdin)
except Exception as e:
    print('  解析失败'); sys.exit()
if 'error' in d:
    print('  ERROR:', d['error'].get('reason','')[:200]); sys.exit()
t=d['hits']['total']['value'] if isinstance(d['hits']['total'],dict) else d['hits']['total']
print(f'  命中 {t} 条  max_score={d[\"hits\"][\"max_score\"]}')
for h in d['hits']['hits']:
    print(f\"    {h['_score']:.4f}  {h['_source']['name']}\")"
}

echo "########## 2. match vs term：本课核心对比 ##########"

echo "--- 先看看「苹果手机」被 ik_smart 切成什么（搜索时用的分析器）---"
$C -X POST "$ES/l6_shop/_analyze" -H "Content-Type: application/json" -d '{
  "field":"name","text":"苹果手机"}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('  ik_smart 搜索分词:',' | '.join(t['token'] for t in d.get('tokens',[])))"

$C -X POST "$ES/l6_shop/_analyze" -H "Content-Type: application/json" -d '{
  "analyzer":"ik_max_word","text":"苹果手机"}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('  ik_max_word 索引分词:',' | '.join(t['token'] for t in d.get('tokens',[])))"
echo ""

echo "--- A. match 查 name（走分析器，先分词再查）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":"苹果手机"}}}' | show
echo ""

echo "--- B. term 查 name（不分词，直接查词项）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name":"苹果手机"}}}' | show
echo ""

echo "--- C. term 查 name 的单个词「苹果」（索引里有这个词项）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name":"苹果"}}}' | show
echo ""

echo "--- D. term 查 name.raw（keyword，整句精确匹配）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"name.raw":"苹果 iPhone 15 Pro 手机"}}}' | show
echo ""

echo "--- E. term 查 brand（keyword，精确值 Apple）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand":"Apple"}}}' | show
echo ""

echo "--- F. term 查 brand 小写 apple（keyword 不分词不归一化 → 应为 0 条）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand":"apple"}}}' | show
echo ""

echo "--- G. match 查 brand（keyword 字段用 match，也能查，但无分词意义）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"brand":"Apple"}}}' | show
echo ""

echo "########## 3. match 的 operator：and vs or ##########"
echo "--- 默认 operator=or（任一词命中即可）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":{"query":"苹果 华为","operator":"or"}}}}' | show
echo ""

echo "--- operator=and（所有词都要命中）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":{"query":"苹果 华为","operator":"and"}}}}' | show
echo ""

echo "--- minimum_should_match: 2 个词至少匹配 1 个 ---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match":{"name":{"query":"苹果 华为","minimum_should_match":1}}}}' | show
echo ""

echo "########## 4. match_phrase：短语查询，词序也要对 ##########"
echo "--- match_phrase 「苹果 手机」（原文里这两个词不相邻）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match_phrase":{"name":"苹果手机"}}}' | show
echo ""

echo "--- match_phrase 「iPhone 15」（相邻且顺序一致）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match_phrase":{"name":"iPhone 15"}}}' | show
echo ""

echo "--- match_phrase 加 slop=2 放宽（允许中间隔词）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "query":{"match_phrase":{"name":{"query":"苹果 手机","slop":3}}}}' | show
echo ""

echo "########## DONE-2 ##########"

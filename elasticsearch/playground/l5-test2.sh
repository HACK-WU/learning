#!/bin/bash
# 课 5 补充实测：multi-fields 用本机已装的分析器
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 9-B. multi-fields：一个字段三种身份（用已装分析器）##########"
$C -X DELETE "$ES/l5_multi" > /dev/null 2>&1
$C -X PUT "$ES/l5_multi" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "title":{
      "type":"text",
      "analyzer":"ik_max_word",
      "search_analyzer":"ik_smart",
      "fields":{
        "raw":{"type":"keyword"},
        "en":{"type":"text","analyzer":"english"},
        "std":{"type":"text","analyzer":"standard"}
      }}}}}'
echo ""

echo "--- 写入一条 ---"
$C -X POST "$ES/l5_multi/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "title":"中国人民银行发行数字货币"}'
echo ""

echo "--- 同一句话，三种身份的分词结果 ---"
echo "[title 主字段 ik_max_word]"
$C -X POST "$ES/l5_multi/_analyze" -H "Content-Type: application/json" -d '{
  "field":"title","text":"中国人民银行发行数字货币"}' | python -c "import sys,json;d=json.load(sys.stdin);print(' | '.join(t['token'] for t in d.get('tokens',[])))"

echo "[title.std standard 逐字]"
$C -X POST "$ES/l5_multi/_analyze" -H "Content-Type: application/json" -d '{
  "field":"title.std","text":"中国人民银行发行数字货币"}' | python -c "import sys,json;d=json.load(sys.stdin);print(' | '.join(t['token'] for t in d.get('tokens',[])))"

echo "[title.raw keyword 不分词]"
$C -X POST "$ES/l5_multi/_analyze" -H "Content-Type: application/json" -d '{
  "field":"title.raw","text":"中国人民银行发行数字货币"}' | python -c "import sys,json;d=json.load(sys.stdin);print(' | '.join(t['token'] for t in d.get('tokens',[])))"
echo ""

echo "--- 搜索对比：同一句查询，查主字段 vs 查 raw ---"
echo "[match 查 title → ik_smart 切4词，应命中]"
$C -X POST "$ES/l5_multi/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"match":{"title":"中国人民银行"}}}'
echo ""
echo "[term 查 title.raw → 必须整句完全相等，单查「中国人民银行」应不命中]"
$C -X POST "$ES/l5_multi/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"term":{"title.raw":"中国人民银行"}}}'
echo ""
echo "[term 查 title.raw → 整句完全相等，应命中]"
$C -X POST "$ES/l5_multi/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"term":{"title.raw":"中国人民银行发行数字货币"}}}'
echo ""

echo "--- 排序/聚合：text 不行，raw 可以 ---"
echo "[对 title 排序 → 报错]"
$C -X POST "$ES/l5_multi/_search" -H "Content-Type: application/json" -d '{
  "sort":[{"title":"asc"}]}' | head -c 400
echo ""
echo "[对 title.raw 排序 → 成功]"
$C -X POST "$ES/l5_multi/_search?filter_path=hits.total,hits.hits._source" -H "Content-Type: application/json" -d '{
  "sort":[{"title.raw":"asc"}]}'
echo ""

echo "########## 14. 翻车演示：数字写成字符串会怎样 ##########"
$C -X DELETE "$ES/l5_trap" > /dev/null 2>&1
$C -X POST "$ES/l5_trap/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{"price":"19.9"}'
echo ""
echo "--- 看类型（应为 text+keyword，不是 float）---"
$C "$ES/l5_trap/_mapping"
echo ""
echo "--- 那么 range 查询还能用吗？查 price>=10 ---"
$C -X POST "$ES/l5_trap/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"range":{"price":{"gte":10}}}}'
echo ""
echo "--- 用 price.keyword 做 range（字符串比较，结果荒唐）---"
$C -X POST "$ES/l5_trap/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"range":{"price.keyword":{"gte":"10"}}}}'
echo ""

echo "########## 15. 关闭动态映射 dynamic:false ##########"
$C -X DELETE "$ES/l5_noDyn" > /dev/null 2>&1
$C -X PUT "$ES/l5_noDyn" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"dynamic":false,"properties":{"title":{"type":"text"}}}}'
echo ""
echo "--- 写入未知字段（不报错，但不索引）---"
$C -X POST "$ES/l5_noDyn/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "title":"测试","ghost":"我是幽灵字段"}'
echo ""
echo "--- 映射里没有 ghost ---"
$C "$ES/l5_noDyn/_mapping"
echo ""
echo "--- 但 _source 里能看到它（只是搜不到）---"
$C "$ES/l5_noDyn/_doc/1"
echo ""
echo "--- 搜 ghost 字段：0 条 ---"
$C -X POST "$ES/l5_noDyn/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"match":{"ghost":"幽灵"}}}'
echo ""
echo "########## DONE ##########"

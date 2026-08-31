#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== 环境检查 ==="
curl.exe -s -k -u elastic:$PW "https://localhost:9200?filter_path=version.number,name"
echo ""
echo "--- 现有索引 ---"
curl.exe -s -k -u elastic:$PW "$ES/_cat/indices?v"
echo ""

echo "########## 0. 建课6专用索引 l6_shop（复用课5的设计）##########"
$C -X DELETE "$ES/l6_shop" > /dev/null 2>&1
$C -X PUT "$ES/l6_shop" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "name":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart",
            "fields":{"raw":{"type":"keyword"}}},
    "brand":{"type":"keyword"},
    "price":{"type":"scaled_float","scaling_factor":100},
    "stock":{"type":"integer"},
    "tags":{"type":"keyword"},
    "on_sale":{"type":"boolean"},
    "created_at":{"type":"date"}}}}'
echo ""

echo "--- 批量写入 8 条商品 ---"
$C -X POST "$ES/l6_shop/_bulk?refresh=true" -H "Content-Type: application/json" -d '
{"index":{"_id":"1"}}
{"name":"苹果 iPhone 15 Pro 手机","brand":"Apple","price":7999.00,"stock":50,"tags":["手机","旗舰"],"on_sale":true,"created_at":"2026-08-01"}
{"index":{"_id":"2"}}
{"name":"华为 Mate 60 Pro 手机","brand":"Huawei","price":6999.00,"stock":30,"tags":["手机","旗舰"],"on_sale":true,"created_at":"2026-08-05"}
{"index":{"_id":"3"}}
{"name":"小米 14 手机","brand":"Xiaomi","price":3999.00,"stock":100,"tags":["手机","性价比"],"on_sale":true,"created_at":"2026-07-20"}
{"index":{"_id":"4"}}
{"name":"苹果 MacBook Pro 笔记本电脑","brand":"Apple","price":12999.00,"stock":20,"tags":["电脑","旗舰"],"on_sale":false,"created_at":"2026-06-15"}
{"index":{"_id":"5"}}
{"name":"联想 ThinkPad 笔记本电脑","brand":"Lenovo","price":8999.00,"stock":15,"tags":["电脑","商务"],"on_sale":true,"created_at":"2026-08-10"}
{"index":{"_id":"6"}}
{"name":"华为 MateBook 笔记本电脑","brand":"Huawei","price":7499.00,"stock":25,"tags":["电脑","轻薄"],"on_sale":false,"created_at":"2026-07-01"}
{"index":{"_id":"7"}}
{"name":"苹果 AirPods Pro 耳机","brand":"Apple","price":1799.00,"stock":200,"tags":["耳机","配件"],"on_sale":true,"created_at":"2026-08-20"}
{"index":{"_id":"8"}}
{"name":"小米 红米 Note 13 手机","brand":"Xiaomi","price":999.00,"stock":300,"tags":["手机","入门"],"on_sale":true,"created_at":"2026-08-25"}
'
echo ""
echo "--- 确认 8 条 ---"
$C "$ES/l6_shop/_count"
echo ""

echo "########## 1. query vs filter 上下文：核心对比 ##########"
echo "--- A. query 上下文（会算分）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":3,
  "query":{"term":{"brand":"Apple"}},
  "explain":false}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('max_score =', d['hits']['max_score'])
for h in d['hits']['hits']:
    print(f\"  score={h['_score']}  {h['_source']['name']}\")"
echo ""

echo "--- B. filter 上下文（不打分，score 恒为 0）---"
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":3,
  "query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('max_score =', d['hits']['max_score'])
for h in d['hits']['hits']:
    print(f\"  score={h['_score']}  {h['_source']['name']}\")"
echo ""

echo "########## DONE-1 ##########"

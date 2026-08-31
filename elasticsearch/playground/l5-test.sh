#!/bin/bash
# 课 5 实测脚本：动态映射 / 显式映射 / 映射不可改 / multi-fields / 模板
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 1. 动态映射：写入各类数据，看 ES 推断出什么类型 ##########"
$C -X DELETE "$ES/l5_auto" > /dev/null 2>&1
$C -X POST "$ES/l5_auto/_doc?refresh=true" -H "Content-Type: application/json" -d '{
  "title":"iPhone 15 Pro",
  "price":7999,
  "score":19.9,
  "views":1024,
  "on_sale":true,
  "created_at":"2026-08-31",
  "tags":["手机","苹果"]
}'
echo ""
echo "--- GET l5_auto/_mapping ---"
$C "$ES/l5_auto/_mapping"
echo ""

echo "########## 2. text vs keyword：同一字段两种身份 ##########"
echo "--- title 字段的映射片段 ---"
$C "$ES/l5_auto/_mapping/field/title"
$C "$ES/l5_auto/_mapping/field/price"
$C "$ES/l5_auto/_mapping/field/score"
$C "$ES/l5_auto/_mapping/field/tags"
echo ""

echo "########## 3. 用 term 查 keyword 子字段 vs text 字段 ##########"
echo "--- term 查 title.keyword（精确匹配整句，应命中1条）---"
$C -X POST "$ES/l5_auto/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"term":{"title.keyword":"iPhone 15 Pro"}}}'
echo ""
echo "--- term 查 title（text已分词，查整句应命中0条）---"
$C -X POST "$ES/l5_auto/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"term":{"title":"iPhone 15 Pro"}}}'
echo ""
echo "--- match 查 title（分词匹配，应命中）---"
$C -X POST "$ES/l5_auto/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{
  "query":{"match":{"title":"iPhone 15 Pro"}}}'
echo ""

echo "########## 4. 映射不可改：尝试把 price 从 long 改成 text ##########"
$C -X PUT "$ES/l5_auto/_mapping" -H "Content-Type: application/json" -d '{
  "properties":{"price":{"type":"text"}}}'
echo ""

echo "########## 5. 映射可添加：新增一个字段 ##########"
$C -X PUT "$ES/l5_auto/_mapping" -H "Content-Type: application/json" -d '{
  "properties":{"brand":{"type":"keyword"}}}'
echo ""
echo "--- 确认 brand 已加入 ---"
$C "$ES/l5_auto/_mapping/field/brand"
echo ""

echo "########## 6. 显式映射：一开始就定好规矩 ##########"
$C -X DELETE "$ES/l5_shop" > /dev/null 2>&1
$C -X PUT "$ES/l5_shop" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{
    "properties":{
      "name":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart"},
      "brand":{"type":"keyword"},
      "price":{"type":"scaled_float","scaling_factor":100},
      "stock":{"type":"integer"},
      "on_sale":{"type":"boolean"},
      "created_at":{"type":"date"}
    }}}'
echo ""
echo "--- 确认映射 ---"
$C "$ES/l5_shop/_mapping"
echo ""

echo "########## 7. keyword 与 numeric 的误用：日期写成字符串会怎样 ##########"
echo "--- 写入正确的 date ---"
$C -X POST "$ES/l5_shop/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "name":"苹果手机 iPhone 15","brand":"Apple","price":7999.00,"stock":50,"on_sale":true,"created_at":"2026-08-31T10:00:00Z"}'
echo ""
echo "--- 尝试写入非法日期（应报错）---"
$C -X POST "$ES/l5_shop/_doc/2?refresh=true" -H "Content-Type: application/json" -d '{
  "name":"测试商品","brand":"Test","price":99.9,"stock":1,"on_sale":true,"created_at":"昨天"}'
echo ""

echo "########## 8. 聚合排序：text 字段不能直接聚合 ##########"
echo "--- 对 text 字段 name 做 terms 聚合（应报错）---"
$C -X POST "$ES/l5_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,"aggs":{"by_name":{"terms":{"field":"name"}}}}'
echo ""
echo "--- 对 keyword 字段 brand 做 terms 聚合（应成功）---"
$C -X POST "$ES/l5_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,"aggs":{"by_brand":{"terms":{"field":"brand"}}}}'
echo ""

echo "########## 9. 多字段 multi-fields：一个字段多种身份 ##########"
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
        "py":{"type":"text","analyzer":"pinyin"}
      }}}}}'
echo ""

echo "########## 10. 动态模板 dynamic_templates ##########"
$C -X DELETE "$ES/l5_tpl" > /dev/null 2>&1
$C -X PUT "$ES/l5_tpl" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{
    "dynamic_templates":[
      {"strings_as_keyword":{
        "match_mapping_type":"string",
        "mapping":{"type":"keyword","ignore_above":256}}}],
    "properties":{"content":{"type":"text","analyzer":"ik_max_word"}}}}'
echo ""
$C -X POST "$ES/l5_tpl/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{
  "content":"中国人民银行的货币政策","author":"张三","status":"published"}'
echo ""
echo "--- 验证：author/status 应被模板变成 keyword，而非 text ---"
$C "$ES/l5_tpl/_mapping"
echo ""

echo "########## 11. 严格模式 strict：禁止未知字段 ##########"
$C -X DELETE "$ES/l5_strict" > /dev/null 2>&1
$C -X PUT "$ES/l5_strict" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"dynamic":"strict","properties":{"title":{"type":"text"}}}}'
echo ""
echo "--- 写入未知字段（应被拒绝）---"
$C -X POST "$ES/l5_strict/_doc/1" -H "Content-Type: application/json" -d '{
  "title":"测试","unknown_field":"我不该被写进来"}'
echo ""

echo "########## 12. 索引模板 index template ##########"
$C -X PUT "$ES/_index_template/l5_logs_template" -H "Content-Type: application/json" -d '{
  "index_patterns":["l5_logs-*"],
  "priority":100,
  "template":{
    "settings":{"number_of_shards":1,"number_of_replicas":0,"refresh_interval":"5s"},
    "mappings":{
      "dynamic_templates":[{"strings_as_keyword":{"match_mapping_type":"string","mapping":{"type":"keyword"}}}],
      "properties":{
        "@timestamp":{"type":"date"},
        "message":{"type":"text","analyzer":"ik_max_word"}}}}}'
echo ""
echo "--- 创建一个符合模式的索引，不写 mapping ---"
$C -X PUT "$ES/l5_logs-2026.08.31"
echo ""
echo "--- 看它是否自动套用了模板 ---"
$C "$ES/l5_logs-2026.08.31/_mapping"
echo ""

echo "########## 13. ignore_above 验证 ##########"
$C -X DELETE "$ES/l5_ignore" > /dev/null 2>&1
$C -X PUT "$ES/l5_ignore" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{"tag":{"type":"keyword","ignore_above":5}}}}'
echo ""
$C -X POST "$ES/l5_ignore/_doc/1?refresh=true" -H "Content-Type: application/json" -d '{"tag":"abc"}'
echo ""
$C -X POST "$ES/l5_ignore/_doc/2?refresh=true" -H "Content-Type: application/json" -d '{"tag":"abcdefghij"}'
echo ""
echo "--- tag=abc 应命中，tag=abcdefghij 应不命中（超长不索引）---"
$C -X POST "$ES/l5_ignore/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{"query":{"term":{"tag":"abc"}}}'
echo ""
$C -X POST "$ES/l5_ignore/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{"query":{"term":{"tag":"abcdefghij"}}}'
echo ""
echo "########## DONE ##########"

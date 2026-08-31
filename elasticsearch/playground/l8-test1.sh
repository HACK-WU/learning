#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 建课8专用索引 l8_orders（为讲聚合设计）##########"
$C -X DELETE "$ES/l8_orders" > /dev/null 2>&1
$C -X PUT "$ES/l8_orders" -H "Content-Type: application/json" -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "order_id":{"type":"keyword"},
    "brand":{"type":"keyword"},
    "brand_text":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart"},
    "category":{"type":"keyword"},
    "product":{"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart","fields":{"keyword":{"type":"keyword","ignore_above":256}}},
    "price":{"type":"double"},
    "qty":{"type":"integer"},
    "amount":{"type":"double"},
    "status":{"type":"keyword"},
    "city":{"type":"keyword"},
    "sale_date":{"type":"date"},
    "tags":{"type":"keyword"}}}'
echo ""

echo "--- 写入 24 条订单（设计：3品牌×多品类，含状态/城市/时间维度）---"
$C -X POST "$ES/l8_orders/_bulk?refresh=true" -H "Content-Type: application/json" -d '
{"index":{"_id":"1"}}
{"order_id":"O001","brand":"苹果","brand_text":"苹果","category":"手机","product":"iPhone 15 Pro","price":7999,"qty":1,"amount":7999,"status":"已完成","city":"北京","sale_date":"2026-08-01","tags":["新品","热销"]}
{"index":{"_id":"2"}}
{"order_id":"O002","brand":"华为","brand_text":"华为","category":"手机","product":"Mate 60","price":6999,"qty":2,"amount":13998,"status":"已完成","city":"上海","sale_date":"2026-08-02","tags":["自研","热销"]}
{"index":{"_id":"3"}}
{"order_id":"O003","brand":"小米","brand_text":"小米","category":"手机","product":"小米14","price":4999,"qty":1,"amount":4999,"status":"已完成","city":"北京","sale_date":"2026-08-03","tags":["性价比"]}
{"index":{"_id":"4"}}
{"order_id":"O004","brand":"苹果","brand_text":"苹果","category":"电脑","product":"MacBook Pro","price":12999,"qty":1,"amount":12999,"status":"已完成","city":"广州","sale_date":"2026-08-04","tags":["高端"]}
{"index":{"_id":"5"}}
{"order_id":"O005","brand":"华为","brand_text":"华为","category":"电脑","product":"MateBook X","price":8999,"qty":1,"amount":8999,"status":"退款","city":"北京","sale_date":"2026-08-05","tags":["轻薄"]}
{"index":{"_id":"6"}}
{"order_id":"O006","brand":"小米","brand_text":"小米","category":"电脑","product":"小米笔记本","price":5999,"qty":1,"amount":5999,"status":"已完成","city":"深圳","sale_date":"2026-08-06","tags":["性价比"]}
{"index":{"_id":"7"}}
{"order_id":"O007","brand":"苹果","brand_text":"苹果","category":"平板","product":"iPad Air","price":4799,"qty":3,"amount":14397,"status":"已完成","city":"上海","sale_date":"2026-08-07","tags":["教育"]}
{"index":{"_id":"8"}}
{"order_id":"O008","brand":"华为","brand_text":"华为","category":"平板","product":"MatePad","price":3299,"qty":1,"amount":3299,"status":"已完成","city":"北京","sale_date":"2026-08-08","tags":["教育"]}
{"index":{"_id":"9"}}
{"order_id":"O009","brand":"小米","brand_text":"小米","category":"平板","product":"小米平板","price":2599,"qty":2,"amount":5198,"status":"退款","city":"广州","sale_date":"2026-08-09","tags":["性价比"]}
{"index":{"_id":"10"}}
{"order_id":"O010","brand":"苹果","brand_text":"苹果","category":"手机","product":"iPhone 15","price":5999,"qty":1,"amount":5999,"status":"已完成","city":"北京","sale_date":"2026-08-10","tags":["热销"]}
{"index":{"_id":"11"}}
{"order_id":"O011","brand":"华为","brand_text":"华为","category":"手机","product":"P60","price":5488,"qty":1,"amount":5488,"status":"已完成","city":"深圳","sale_date":"2026-08-11","tags":["影像"]}
{"index":{"_id":"12"}}
{"order_id":"O012","brand":"小米","brand_text":"小米","category":"手机","product":"Redmi K70","price":2999,"qty":4,"amount":11996,"status":"已完成","city":"上海","sale_date":"2026-08-12","tags":["性价比","热销"]}
{"index":{"_id":"13"}}
{"order_id":"O013","brand":"苹果","brand_text":"苹果","category":"电脑","product":"MacBook Air","price":8999,"qty":1,"amount":8999,"status":"已完成","city":"广州","sale_date":"2026-08-13","tags":["轻薄"]}
{"index":{"_id":"14"}}
{"order_id":"O014","brand":"华为","brand_text":"华为","category":"电脑","product":"MateBook 14","price":6499,"qty":1,"amount":6499,"status":"已完成","city":"北京","sale_date":"2026-08-14","tags":["办公"]}
{"index":{"_id":"15"}}
{"order_id":"O015","brand":"小米","brand_text":"小米","category":"电脑","product":"Redmi Book","price":4299,"qty":1,"amount":4299,"status":"退款","city":"深圳","sale_date":"2026-08-15","tags":["办公"]}
{"index":{"_id":"16"}}
{"order_id":"O016","brand":"苹果","brand_text":"苹果","category":"平板","product":"iPad Pro","price":8999,"qty":1,"amount":8999,"status":"已完成","city":"上海","sale_date":"2026-08-16","tags":["高端"]}
{"index":{"_id":"17"}}
{"order_id":"O017","brand":"华为","brand_text":"华为","category":"平板","product":"MatePad Pro","price":5199,"qty":2,"amount":10398,"status":"已完成","city":"北京","sale_date":"2026-08-17","tags":["高端"]}
{"index":{"_id":"18"}}
{"order_id":"O018","brand":"小米","brand_text":"小米","category":"平板","product":"小米平板6","price":1999,"qty":1,"amount":1999,"status":"已完成","city":"广州","sale_date":"2026-08-18","tags":["性价比"]}
{"index":{"_id":"19"}}
{"order_id":"O019","brand":"苹果","brand_text":"苹果","category":"手机","product":"iPhone 15 Pro Max","price":9999,"qty":1,"amount":9999,"status":"已完成","city":"北京","sale_date":"2026-08-19","tags":["高端","新品"]}
{"index":{"_id":"20"}}
{"order_id":"O020","brand":"华为","brand_text":"华为","category":"手机","product":"Mate 60 Pro","price":7999,"qty":1,"amount":7999,"status":"已完成","city":"上海","sale_date":"2026-08-20","tags":["高端","新品"]}
{"index":{"_id":"21"}}
{"order_id":"O021","brand":"小米","brand_text":"小米","category":"手机","product":"小米14 Pro","price":5999,"qty":1,"amount":5999,"status":"已完成","city":"深圳","sale_date":"2026-08-21","tags":["新品"]}
{"index":{"_id":"22"}}
{"order_id":"O022","brand":"苹果","brand_text":"苹果","category":"电脑","product":"iMac","price":10999,"qty":1,"amount":10999,"status":"退款","city":"北京","sale_date":"2026-08-22","tags":["高端"]}
{"index":{"_id":"23"}}
{"order_id":"O023","brand":"华为","brand_text":"华为","category":"电脑","product":"MateBook E","price":7499,"qty":1,"amount":7499,"status":"已完成","city":"广州","sale_date":"2026-08-23","tags":["轻薄"]}
{"index":{"_id":"24"}}
{"order_id":"O024","brand":"小米","brand_text":"小米","category":"电脑","product":"小米台式机","price":4999,"qty":1,"amount":4999,"status":"已完成","city":"上海","sale_date":"2026-08-24","tags":["办公"]}
'
echo ""
echo "--- 确认条数 ---"
$C "$ES/l8_orders/_count"
echo ""
echo "########## DONE-L8-1 ##########"

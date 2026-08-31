#!/bin/bash
export LANG=C.UTF-8
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW -H Content-Type:application/json"
D="/mnt/d/projects/learning/elasticsearch/playground"

echo "===== l8_orders_v2 mapping ====="
$C "https://localhost:9200/l8_orders_v2/_mapping" > "$D/_m.json"
cat "$D/_m.json" | tr ',' '\n' | grep -E '"[a-z_]+":\{"type"' | head -30

echo ""
echo "===== 样例文档 ====="
$C "https://localhost:9200/l8_orders_v2/_search?size=1" | tr ',' '\n' | grep -E '"(brand|region|salesman|category|product|amount|price|unit_price|qty|quantity|sale_date|status|tags)"' | head -20

#!/bin/bash
export LANG=C.UTF-8
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW -H Content-Type:application/json"

echo "===== 3. 索引计数 ====="
for idx in l8_orders l8_orders_v2 l8_text_demo l7_news l6_shop; do
  cnt=$($C "https://localhost:9200/$idx/_count" | grep -o '"count":[0-9]*')
  echo "$idx -> $cnt"
done

echo ""
echo "===== 4. 品牌销售额与均价 (期望 80390/64179/45488, 8849.0/6497.625/4236.5) ====="
cat > /tmp/q1.json <<'EOF'
{"size":0,"aggs":{"by_brand":{"terms":{"field":"brand","size":10},"aggs":{"s":{"sum":{"field":"amount"}},"a":{"avg":{"field":"unit_price"}}}}}}
EOF
$C "https://localhost:9200/l8_orders_v2/_search?size=0" -d @/tmp/q1.json > /tmp/r1.json
python -c "
import json
d=json.load(open('/tmp/r1.json'))
for b in d['aggregations']['by_brand']['buckets']:
    print(f\"{b['key']:<6} cnt={b['doc_count']:<3} sum={b['s']['value']:<10} avg={b['a']['value']}\")
" 2>/dev/null || cat /tmp/r1.json

echo ""
echo "===== 5. 总销售额 (期望 190057) ====="
$C "https://localhost:9200/l8_orders_v2/_search?size=0" -d '{"size":0,"aggs":{"t":{"sum":{"field":"amount"}}}}' | grep -o '"value":[0-9.]*'

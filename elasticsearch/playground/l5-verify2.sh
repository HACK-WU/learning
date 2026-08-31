#!/bin/bash
# 关键验证：long 字段写入 19.9，索引里到底是 19 还是 19.9？
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== 索引里 price 的实际类型 ==="
$C "$ES/l5_shop_bad/_mapping/field/price"
echo ""
echo "=== 逐段探测：range 查询定位真实值 ==="
echo -n "price >= 19.5  : "
$C -X POST "$ES/l5_shop_bad/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{"query":{"range":{"price":{"gte":19.5}}}}'
echo ""
echo -n "price >= 19    : "
$C -X POST "$ES/l5_shop_bad/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{"query":{"range":{"price":{"gte":19}}}}'
echo ""
echo -n "price == 19 (term) : "
$C -X POST "$ES/l5_shop_bad/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{"query":{"term":{"price":19}}}'
echo ""
echo -n "price == 19.9 (term) : "
$C -X POST "$ES/l5_shop_bad/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{"query":{"term":{"price":19.9}}}'
echo ""
echo -n "price < 19.5  : "
$C -X POST "$ES/l5_shop_bad/_search?filter_path=hits.total" -H "Content-Type: application/json" -d '{"query":{"range":{"price":{"lt":19.5}}}}'
echo ""
echo "=== 用 docvalue_fields 直接读索引里的真实值 ==="
$C -X POST "$ES/l5_shop_bad/_search" -H "Content-Type: application/json" -d '{
  "docvalue_fields":[{"field":"price"}],
  "query":{"ids":{"values":["2"]}}}'
echo ""
echo "########## DONE ##########"

#!/bin/bash
# 课 2：用 Stream Load 把 CSV 导入 Doris
# Stream Load 走的是 BE 的 HTTP 端口 8040

echo "=== 拷贝 CSV 到 Doris 容器 ==="
docker cp /tmp/l02data/orders_dump.csv doris-learn:/tmp/orders_dump.csv
docker exec doris-learn bash -c "ls -lh /tmp/orders_dump.csv"

echo ""
echo "=== 开始 Stream Load ==="
START=$(date +%s)

docker exec doris-learn bash -c '
curl -s --location-trusted -u root: \
  -H "format: csv" \
  -H "column_separator: ," \
  -H "columns: order_date,province,city,user_id,product_id,category,quantity,amount,pay_type,status,remark,created_at,updated_at" \
  -H "max_filter_ratio: 0.1" \
  -T /tmp/orders_dump.csv \
  http://127.0.0.1:8040/api/shop/orders/_stream_load
' 2>&1

END=$(date +%s)
echo ""
echo "导入耗时: $((END-START)) 秒"

echo ""
echo "=== 校验行数 ==="
docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "USE shop; SELECT COUNT(*) AS total_rows FROM orders;" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "LOAD_DONE"

#!/bin/bash
# 课 2：从 MySQL 导出 → 导入 Doris（Stream Load）
# 步骤 1：MySQL 导出为 CSV

echo "=== 步骤 1：MySQL 导出 2000 万行到 /tmp ==="
docker exec doris-mysql-demo bash -c "mysql -uroot -proot123 shop -N -e \"
SELECT order_date, province, city, user_id, product_id, category,
       quantity, amount, pay_type, status, remark, created_at, updated_at
FROM orders;\" 2>/dev/null | sed 's/\t/,/g' > /tmp/orders_dump.csv"

docker exec doris-mysql-demo bash -c "ls -lh /tmp/orders_dump.csv && wc -l /tmp/orders_dump.csv"

echo ""
echo "=== 步骤 2：拷到宿主机中转 ==="
mkdir -p /tmp/l02data
docker cp doris-mysql-demo:/tmp/orders_dump.csv /tmp/l02data/orders_dump.csv
ls -lh /tmp/l02data/orders_dump.csv

echo ""
echo "EXPORT_DONE"

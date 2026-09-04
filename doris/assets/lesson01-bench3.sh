#!/bin/bash
# 第一课实测 · 第三轮：量化"只需要 2 列，却读了整行"
MYSQL="docker exec doris-mysql-demo mysql -uroot -proot123 shop -t"

echo "=========== 每行实际占用字节 ==========="
$MYSQL -e "SELECT ROUND(data_length/table_rows) AS bytes_per_row, ROUND(data_length/1024/1024) AS data_mb, table_rows FROM information_schema.tables WHERE table_schema='shop' AND table_name='orders';" 2>/dev/null

echo ""
echo "=========== Q2 真正需要的两列，每行各占多少字节 ==========="
$MYSQL -e "SELECT LENGTH('广东') AS province_bytes_gbk_ascii, ROUND(AVG(LENGTH(province))) AS province_avg_bytes, ROUND(AVG(LENGTH(amount))) AS amount_avg_bytes FROM orders;" 2>/dev/null

echo ""
echo "=========== 只读两列 vs 读整行：MySQL 的行存没有区别 ==========="
start=$(date +%s.%N)
$MYSQL -e "SELECT province, amount FROM orders;" 2>/dev/null > /dev/null
end=$(date +%s.%N)
printf '只读 2 列、不加聚合: %.2f 秒（仍然要读完整行所在的页）\n' "$(echo "$end - $start" | bc)"

start=$(date +%s.%N)
$MYSQL -e "SELECT COUNT(*) FROM orders;" 2>/dev/null > /dev/null
end=$(date +%s.%N)
printf 'COUNT(*)（走主键索引、不读行）: %.2f 秒\n' "$(echo "$end - $start" | bc)"

echo ""
echo "=========== 索引让表的体积增加了多少 ==========="
$MYSQL -e "SELECT ROUND(data_length/1024/1024) AS data_mb, ROUND(index_length/1024/1024) AS index_mb, ROUND((data_length+index_length)/1024/1024) AS total_mb FROM information_schema.tables WHERE table_schema='shop' AND table_name='orders';" 2>/dev/null

echo ""
echo "=========== 插入代价：索引越多写入越慢 ==========="
$MYSQL -e "CREATE TABLE orders_noidx LIKE orders;" 2>/dev/null
$MYSQL -e "ALTER TABLE orders_noidx DROP INDEX idx_prov_amount, DROP INDEX idx_date;" 2>/dev/null
start=$(date +%s.%N)
$MYSQL -e "INSERT INTO orders_noidx (order_date,province,city,user_id,product_id,category,quantity,amount,pay_type,status,remark,created_at,updated_at) SELECT order_date,province,city,user_id,product_id,category,quantity,amount,pay_type,status,remark,created_at,updated_at FROM orders LIMIT 500000;" 2>/dev/null
end=$(date +%s.%N)
printf '无二级索引表插 50 万行: %.2f 秒\n' "$(echo "$end - $start" | bc)"

start=$(date +%s.%N)
$MYSQL -e "INSERT INTO orders (order_date,province,city,user_id,product_id,category,quantity,amount,pay_type,status,remark,created_at,updated_at) SELECT order_date,province,city,user_id,product_id,category,quantity,amount,pay_type,status,remark,created_at,updated_at FROM orders LIMIT 500000;" 2>/dev/null
end=$(date +%s.%N)
printf '带两个二级索引表插 50 万行: %.2f 秒\n' "$(echo "$end - $start" | bc)"

$MYSQL -e "DROP TABLE orders_noidx;" 2>/dev/null
echo ""
echo "DONE"

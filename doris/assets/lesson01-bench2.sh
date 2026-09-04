#!/bin/bash
# 第一课实测 · 第二轮：加索引能救多少？代价是什么？
MYSQL="docker exec doris-mysql-demo mysql -uroot -proot123 shop -t"

echo "=========== 基线：无 province 索引时的 Q2 ==========="
$MYSQL -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null > /dev/null
start=$(date +%s.%N)
$MYSQL -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null > /dev/null
end=$(date +%s.%N)
printf '无索引 Q2 耗时: %.2f 秒\n' "$(echo "$end - $start" | bc)"

echo ""
echo "=========== 每行实际需要 / 实际读取 的字节对比 ==========="
$MYSQL -e "
SELECT
  ROUND(data_length/table_rows)            AS 每行实际占用字节,
  ROUND(data_length/1024/1024)             AS 整表数据MB,
  table_rows                               AS 行数
FROM information_schema.tables
WHERE table_schema='shop' AND table_name='orders';" 2>/dev/null

$MYSQL -e "
SELECT
  province,
  LENGTH(province) AS province字节,
  ROUND(AVG(LENGTH(amount))) AS amount平均字节
FROM orders LIMIT 1;" 2>/dev/null

echo ""
echo "=========== 加联合索引 (province, amount) 的代价 ==========="
start=$(date +%s.%N)
$MYSQL -e "ALTER TABLE orders ADD INDEX idx_prov_amount (province, amount);" 2>/dev/null
end=$(date +%s.%N)
printf '建索引耗时: %.2f 秒\n' "$(echo "$end - $start" | bc)"

$MYSQL -e "
SELECT
  index_name,
  ROUND(stat_value * @@innodb_page_size / 1024 / 1024) AS 索引MB
FROM mysql.innodb_index_stats
WHERE database_name='shop' AND table_name='orders' AND stat_name='size';" 2>/dev/null

$MYSQL -e "SELECT ROUND((data_length+index_length)/1024/1024) AS 加索引后合计MB FROM information_schema.tables WHERE table_schema='shop' AND table_name='orders';" 2>/dev/null

echo ""
echo "=========== 加索引后 Q2 重跑 ==========="
$MYSQL -e "EXPLAIN SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null
$MYSQL -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null > /dev/null
start=$(date +%s.%N)
$MYSQL -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null > /dev/null
end=$(date +%s.%N)
printf '有索引 Q2 耗时: %.2f 秒\n' "$(echo "$end - $start" | bc)"

echo ""
echo "=========== 但换一个维度聚合呢？（索引失效）==========="
$MYSQL -e "EXPLAIN SELECT category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY category ORDER BY total DESC;" 2>/dev/null
start=$(date +%s.%N)
$MYSQL -e "SELECT category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY category ORDER BY total DESC;" 2>/dev/null > /dev/null
end=$(date +%s.%N)
printf '按 category 聚合（无索引）耗时: %.2f 秒\n' "$(echo "$end - $start" | bc)"

echo ""
echo "=========== 两个维度组合（索引又失效）==========="
start=$(date +%s.%N)
$MYSQL -e "SELECT province, category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province, category ORDER BY total DESC LIMIT 10;" 2>/dev/null > /dev/null
end=$(date +%s.%N)
printf '按 province+category 聚合耗时: %.2f 秒\n' "$(echo "$end - $start" | bc)"

#!/bin/bash
# 课 2：补测 —— 点查（Doris 的劣势）+ 存储体积 + 执行计划
DORIS="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"
MYSQL="docker exec doris-mysql-demo mysql -uroot -proot123 shop"

echo "=========== Q5: 点查（OLTP 主场，看 Doris 的劣势）==========="
echo "--- MySQL 主键点查 ---"
S=$(date +%s.%N)
$MYSQL -e "SELECT COUNT(*) FROM orders WHERE id = 12345678;" 2>/dev/null > /dev/null
E=$(date +%s.%N)
printf 'MySQL  : %.4f 秒\n' "$(echo "$E - $S" | bc)"

echo "--- Doris 按 user_id 过滤（无索引，全表扫）---"
S=$(date +%s.%N)
$DORIS -e "USE shop; SELECT COUNT(*) FROM orders WHERE user_id = 12345678;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf 'Doris  : %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "=========== 存储体积对比（关键：压缩率）==========="
echo -n "MySQL 表体积 MB（含索引）: "
$MYSQL -N -e "SELECT ROUND((data_length+index_length)/1024/1024) FROM information_schema.tables WHERE table_schema='shop' AND table_name='orders';" 2>/dev/null

echo "Doris 表体积:"
$DORIS -e "USE shop; SHOW DATA;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "--- Doris 各分片体积 ---"
$DORIS -e "USE shop; SHOW PARTITIONS FROM orders;" 2>/dev/null | grep -vE "^Warning|Using a password" | head -5

echo ""
echo "--- Doris tablet 层面的真实大小 ---"
$DORIS -e "USE shop; SHOW TABLETS FROM orders;" 2>/dev/null | grep -vE "^Warning|Using a password" | head -3

echo ""
echo "=========== 执行计划对比 ==========="
echo "--- MySQL EXPLAIN（Q1）---"
$MYSQL -e "EXPLAIN SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null

echo ""
echo "--- Doris EXPLAIN（Q1）---"
$DORIS -e "USE shop; EXPLAIN SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" | head -40

echo ""
echo "=========== Doris 的 tablet 数（理解 BUCKETS 8 的物理含义）==========="
$DORIS -e "USE shop; SHOW TABLETS FROM orders;" 2>/dev/null | grep -vE "^Warning|Using a password" | wc -l

echo ""
echo "BENCH2_DONE"

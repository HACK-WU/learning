#!/bin/bash
# 课 2：性能对比 —— 同一批数据、同一条 SQL，MySQL vs Doris
# MySQL 侧数据来自课 1（2000 万行，含后来新增的 50 万行 = 2050 万行，与 Doris 同口径）

DORIS="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"
MYSQL="docker exec doris-mysql-demo mysql -uroot -proot123 shop"

echo "=========== 行数对齐校验 ==========="
echo -n "MySQL  : "
$MYSQL -N -e "SELECT COUNT(*) FROM orders;" 2>/dev/null
echo -n "Doris  : "
$DORIS -N -e "USE shop; SELECT COUNT(*) FROM orders;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 存储体积对比 ==========="
echo -n "MySQL 表体积(MB): "
$MYSQL -N -e "SELECT ROUND((data_length+index_length)/1024/1024) FROM information_schema.tables WHERE table_schema='shop' AND table_name='orders';" 2>/dev/null
echo "Doris 表体积:"
$DORIS -e "USE shop; SHOW DATA FROM orders;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== Q1: 按省分组聚合（课 1 那条"迟到的报表"） ==========="
echo "--- MySQL ---"
S=$(date +%s.%N)
$MYSQL -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null > /dev/null
E=$(date +%s.%N)
printf 'MySQL: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo "--- Doris ---"
$DORIS -e "USE shop; SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
S=$(date +%s.%N)
$DORIS -e "USE shop; SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf 'Doris: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "--- Doris 实际结果 ---"
$DORIS -e "USE shop; SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== Q2: 换维度（按品类），MySQL 索引失效的场景 ==========="
echo "--- MySQL ---"
S=$(date +%s.%N)
$MYSQL -e "SELECT category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY category ORDER BY total DESC;" 2>/dev/null > /dev/null
E=$(date +%s.%N)
printf 'MySQL: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo "--- Doris ---"
$DORIS -e "USE shop; SELECT category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY category ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
S=$(date +%s.%N)
$DORIS -e "USE shop; SELECT category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY category ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf 'Doris: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "=========== Q3: 二维聚合（省 × 品类）==========="
echo "--- MySQL ---"
S=$(date +%s.%N)
$MYSQL -e "SELECT province, category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province, category ORDER BY total DESC LIMIT 10;" 2>/dev/null > /dev/null
E=$(date +%s.%N)
printf 'MySQL: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo "--- Doris ---"
$DORIS -e "USE shop; SELECT province, category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province, category ORDER BY total DESC LIMIT 10;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
S=$(date +%s.%N)
$DORIS -e "USE shop; SELECT province, category, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province, category ORDER BY total DESC LIMIT 10;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf 'Doris: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "=========== Q4: 带时间过滤的聚合 ==========="
echo "--- MySQL ---"
S=$(date +%s.%N)
$MYSQL -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders WHERE order_date >= '2025-12-01' AND order_date < '2026-01-01' GROUP BY province ORDER BY total DESC;" 2>/dev/null > /dev/null
E=$(date +%s.%N)
printf 'MySQL: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo "--- Doris ---"
$DORIS -e "USE shop; SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders WHERE order_date >= '2025-12-01' AND order_date < '2026-01-01' GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
S=$(date +%s.%N)
$DORIS -e "USE shop; SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders WHERE order_date >= '2025-12-01' AND order_date < '2026-01-01' GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf 'Doris: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "=========== Q5: 点查（OLTP 主场，看 Doris 的劣势）==========="
echo "--- MySQL（主键点查）---"
S=$(date +%s.%N)
$MYSQL -e "SELECT COUNT(*) FROM orders WHERE id = 12345678;" 2>/dev/null > /dev/null
E=$(date +%s.%N)
printf 'MySQL: %.4f 秒\n' "$(echo "$E - $S" | bc)"

echo "--- Doris（全表扫，没有主键索引）---"
S=$(date +%s.%N)
$DORIS -e "USE shop; SELECT COUNT(*) FROM orders WHERE user_id = 12345678;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf 'Doris: %.2f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "BENCH_DONE"

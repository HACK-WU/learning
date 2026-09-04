#!/bin/bash
# 课 3：三模型对比 —— 存储体积 + 查询耗时 + 聚合语义验证
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 存储体积对比 ==========="
$D -e "SHOW DATA;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 每表行数 ==========="
$D -e "
SELECT 'orders_dup（明细）' AS tbl, COUNT(*) AS rows FROM orders_dup
UNION ALL SELECT 'orders_agg（聚合）', COUNT(*) FROM orders_agg;
" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== Q1: 省×市 聚合查询耗时对比 ==========="
echo "--- 明细表 orders_dup（每次扫 2050 万行）---"
for i in 1 2 3; do
  S=$(date +%s.%N)
  $D -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders_dup GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
  E=$(date +%s.%N)
  printf '  第 %d 次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done

echo "--- 聚合表 orders_agg（只扫 18.8 万行）---"
for i in 1 2 3; do
  S=$(date +%s.%N)
  $D -e "SELECT province, SUM(order_cnt) c, ROUND(SUM(amount_sum)) total FROM orders_agg GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
  E=$(date +%s.%N)
  printf '  第 %d 次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done

echo ""
echo "=========== Q1 结果一致性校验（明细 vs 聚合，必须完全相同）==========="
echo "--- 明细表 ---"
$D -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders_dup GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- 聚合表 ---"
$D -e "SELECT province, SUM(order_cnt) c, ROUND(SUM(amount_sum)) total FROM orders_agg GROUP BY province ORDER BY total DESC;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== Q2: 按日期聚合（时间维度）==========="
echo "--- 明细表 ---"
S=$(date +%s.%N)
$D -e "SELECT order_date, COUNT(*) c, ROUND(SUM(amount)) total FROM orders_dup GROUP BY order_date ORDER BY order_date DESC LIMIT 10;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf '  %.3f 秒\n' "$(echo "$E - $S" | bc)"
echo "--- 聚合表 ---"
S=$(date +%s.%N)
$D -e "SELECT order_date, SUM(order_cnt) c, ROUND(SUM(amount_sum)) total FROM orders_agg GROUP BY order_date ORDER BY order_date DESC LIMIT 10;" 2>/dev/null | grep -vE "^Warning|Using a password" > /dev/null
E=$(date +%s.%N)
printf '  %.3f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "=========== Aggregate 语义验证：REPLACE 保留哪一条？==========="
$D -e "SELECT order_date, province, city, order_cnt, amount_sum, last_status FROM orders_agg WHERE order_date='2025-01-01' AND province='广东' LIMIT 3;" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- 对照：明细表里这个分组的 status 有哪些值 ---"
$D -e "SELECT DISTINCT status FROM orders WHERE order_date='2025-01-01' AND province='广东' AND city=(SELECT city FROM orders WHERE order_date='2025-01-01' AND province='广东' LIMIT 1);" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 明细表能查到单笔订单吗？聚合表呢？==========="
echo "--- 明细表：查某用户某天的订单 ---"
$D -e "SELECT COUNT(*) FROM orders_dup WHERE user_id=12345 AND order_date='2025-06-01';" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- 聚合表：这个查询根本没法做（没有 user_id 列）---"
$D -e "SELECT COUNT(*) FROM orders_agg WHERE user_id=12345;" 2>&1 | grep -vE "^Warning|Using a password" | head -3

echo ""
echo "BENCH_DONE"

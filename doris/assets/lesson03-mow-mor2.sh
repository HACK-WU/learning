#!/bin/bash
# 课 3：MOW vs MOR 修正版 —— 用 orders_dup 作为数据源（它有全部列）
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 先验证导入语句能跑通 ==========="
$D -e "SELECT order_date, province, city, user_id, amount, status, updated_at FROM orders_dup LIMIT 2;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 清空两表重新开始 ==========="
$D -e "TRUNCATE TABLE orders_uniq_mow;" 2>/dev/null >/dev/null
$D -e "TRUNCATE TABLE orders_uniq_mor;" 2>/dev/null >/dev/null
echo "已清空"

echo ""
echo "=========== MOW 表：6 批覆盖式导入（每批 30 万行，主键重合）==========="
for batch in 1 2 3 4 5 6; do
  S=$(date +%s.%N)
  $D -e "
  INSERT INTO orders_uniq_mow
  SELECT order_date, province, city, user_id, amount, status, updated_at
  FROM orders_dup LIMIT 300000;" 2>/dev/null >/dev/null
  E=$(date +%s.%N)
  printf '  第 %d 批: %.2f 秒\n' "$batch" "$(echo "$E - $S" | bc)"
done

echo ""
echo "MOW 行数："
$D -e "SELECT COUNT(*) FROM orders_uniq_mow;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== MOR 表：同样 6 批 ==========="
for batch in 1 2 3 4 5 6; do
  S=$(date +%s.%N)
  $D -e "
  INSERT INTO orders_uniq_mor
  SELECT order_date, province, city, user_id, amount, status, updated_at
  FROM orders_dup LIMIT 300000;" 2>/dev/null >/dev/null
  E=$(date +%s.%N)
  printf '  第 %d 批: %.2f 秒\n' "$batch" "$(echo "$E - $S" | bc)"
done

echo ""
echo "MOR 行数："
$D -e "SELECT COUNT(*) FROM orders_uniq_mor;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 版本堆积对比（核心差异）==========="
echo "--- MOW（写时合并：导入时就消掉了重复键）---"
$D --batch -e "SHOW TABLETS FROM orders_uniq_mow;" 2>/dev/null | awk -F'\t' 'NR>1{printf "  tablet %s: VersionCount=%s RowCount=%s\n", $1, $16, $11}'
echo "--- MOR（读时合并：版本堆积）---"
$D --batch -e "SHOW TABLETS FROM orders_uniq_mor;" 2>/dev/null | awk -F'\t' 'NR>1{printf "  tablet %s: VersionCount=%s RowCount=%s\n", $1, $16, $11}'

echo ""
echo "=========== 查询耗时对比 ==========="
echo "--- MOW ---"
for i in 1 2 3; do
  S=$(date +%s.%N)
  $D -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) t FROM orders_uniq_mow GROUP BY province;" 2>/dev/null >/dev/null
  E=$(date +%s.%N)
  printf '  第 %d 次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done
echo "--- MOR ---"
for i in 1 2 3; do
  S=$(date +%s.%N)
  $D -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) t FROM orders_uniq_mor GROUP BY province;" 2>/dev/null >/dev/null
  E=$(date +%s.%N)
  printf '  第 %d 次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done

echo ""
echo "=========== 结果一致性（两表应完全相同）==========="
echo "--- MOW ---"
$D -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) t FROM orders_uniq_mow GROUP BY province ORDER BY c DESC LIMIT 4;" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- MOR ---"
$D -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) t FROM orders_uniq_mor GROUP BY province ORDER BY c DESC LIMIT 4;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== EXPLAIN 对比 ==========="
echo "--- MOW ---"
$D -e "EXPLAIN SELECT province, COUNT(*) c FROM orders_uniq_mow GROUP BY province;" 2>/dev/null | grep -iE "aggregate|scan|tablet|cardinality" | head -8
echo "--- MOR ---"
$D -e "EXPLAIN SELECT province, COUNT(*) c FROM orders_uniq_mor GROUP BY province;" 2>/dev/null | grep -iE "aggregate|scan|tablet|cardinality" | head -8

echo ""
echo "MOWMOR2_DONE"

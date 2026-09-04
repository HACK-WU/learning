#!/bin/bash
# 课 4：按天分区实测（修正 source 方式）—— 分区过多的代价
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 重建按天分区表，用逐条 ALTER 建 365 个分区 ==========="
S=$(date +%s)
for i in $(seq 0 364); do
  D1=$(date -d "2025-01-01 +$i days" +%Y-%m-%d)
  D2=$(date -d "2025-01-01 +$((i+1)) days" +%Y-%m-%d)
  PN=$(date -d "2025-01-01 +$i days" +%Y%m%d)
  $D -e "ALTER TABLE t_part_day ADD PARTITION IF NOT EXISTS p$PN VALUES [('$D1'), ('$D2'));" 2>/dev/null >/dev/null
done
E=$(date +%s)
echo "  建 365 个分区耗时: $((E-S)) 秒"

echo ""
echo "=========== 分区数与 tablet 数对比 ==========="
echo "--- 按天分区表 (t_part_day) ---"
echo -n "  分区数: "
$D --batch -e "SHOW PARTITIONS FROM t_part_day;" 2>/dev/null | tail -n +2 | wc -l
echo -n "  tablet 数: "
$D --batch -e "SHOW TABLETS FROM t_part_day;" 2>/dev/null | tail -n +2 | wc -l

echo ""
echo "--- 按月分区表 (t_part_month) ---"
echo -n "  分区数: "
$D --batch -e "SHOW PARTITIONS FROM t_part_month;" 2>/dev/null | tail -n +2 | wc -l
echo -n "  tablet 数: "
$D --batch -e "SHOW TABLETS FROM t_part_month;" 2>/dev/null | tail -n +2 | wc -l

echo ""
echo "--- 不分区表 (t_nopart_user) ---"
echo -n "  tablet 数: "
$D --batch -e "SHOW TABLETS FROM t_nopart_user;" 2>/dev/null | tail -n +2 | wc -l

echo ""
echo "=========== 导入数据到按天分区表 ==========="
S=$(date +%s)
$D -e "INSERT INTO t_part_day SELECT order_date, province, city, user_id, amount, quantity FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01';" 2>/dev/null >/dev/null
E=$(date +%s)
echo "  耗时: $((E-S)) 秒"
echo -n "  行数: "
$D --batch -e "SELECT COUNT(*) FROM t_part_day;" 2>/dev/null | tail -1

echo ""
echo "=========== 关键对比：按天 vs 按月，查同一个月的数据 ==========="
echo "--- 按天分区表：查 2025 年 6 月（要扫 30 个分区）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM t_part_day WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "partitions=|tablets=|cardinality=" | head -4

echo ""
echo "--- 按月分区表：查 2025 年 6 月（只扫 1 个分区）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM t_part_month WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "partitions=|tablets=|cardinality=" | head -4

echo ""
echo "--- 按天分区表：查单日（只扫 1 个分区，这是按天的优势）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM t_part_day WHERE order_date = '2025-06-15';" 2>/dev/null | grep -iE "partitions=|tablets=|cardinality=" | head -4

echo ""
echo "--- 按月分区表：查单日（仍要扫整个 6 月分区）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM t_part_month WHERE order_date = '2025-06-15';" 2>/dev/null | grep -iE "partitions=|tablets=|cardinality=" | head -4

echo ""
echo "=========== 结论：分区粒度的权衡 ==========="
echo "  按天: 365 分区，单日查询最精准，但 tablet 膨胀、元数据压力大"
echo "  按月: 24 分区，月度查询高效，元数据轻"
echo "  选哪个取决于查询模式，不是越细越好"

echo ""
echo "DAY4_DONE"

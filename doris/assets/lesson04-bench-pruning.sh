#!/bin/bash
# 课 4：核心实验 —— 分区裁剪 + 分桶倾斜对比
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 实验 1：分桶键倾斜对比（课 3 的遗留欠账）==========="
echo ""
echo "--- A: 按 province 分桶（8 个不同值，课 2 的坑）---"
$D --batch -e "SHOW TABLETS FROM t_nopart_prov;" 2>/dev/null | awk -F'\t' 'NR>1{sum+=$11; if($11>max)max=$11; if(min==""||$11<min)min=$11; n++} END{printf "  桶数=%d 平均=%d 最大=%d 最小=%d 倾斜比=%.2f\n", n, sum/n, max, min, max/min}'

echo "--- B: 按 user_id 分桶（183 万不同值）---"
$D --batch -e "SHOW TABLETS FROM t_nopart_user;" 2>/dev/null | awk -F'\t' 'NR>1{sum+=$11; if($11>max)max=$11; if(min==""||$11<min)min=$11; n++} END{printf "  桶数=%d 平均=%d 最大=%d 最小=%d 倾斜比=%.2f\n", n, sum/n, max, min, max/min}'

echo "--- C: 按月分区 + 按 user_id 分桶（每分区 8 桶）---"
$D --batch -e "SHOW TABLETS FROM t_part_month;" 2>/dev/null | awk -F'\t' 'NR>1{if($11>0){sum+=$11; if($11>max)max=$11; if(min==""||$11<min)min=$11; n++}} END{printf "  非空桶数=%d 平均=%d 最大=%d 最小=%d 倾斜比=%.2f\n", n, sum/n, max, min, max/min}'

echo ""
echo "=========== 实验 2：分区裁剪（本课核心）==========="
echo "查询：统计 2025 年 6 月的数据"

echo ""
echo "--- 不分区表（t_nopart_user，必须扫全表 2050 万行）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM t_nopart_user WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "tablets=|cardinality=|rows=|PARTITION|VOlapScan" | head -8

echo ""
echo "--- 分区表（t_part_month，应该只扫 1 个分区）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM t_part_month WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "tablets=|cardinality=|rows=|PARTITION|VOlapScan" | head -8

echo ""
echo "=========== 实验 3：实际查询耗时对比 ============"
echo "--- 不分区表 ---"
S=$(date +%s.%N)
$D -e "SELECT COUNT(*), ROUND(SUM(amount)) FROM t_nopart_user WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null >/dev/null
E=$(date +%s.%N)
printf '  %.3f 秒\n' "$(echo "$E - $S" | bc)"

echo "--- 分区表 ---"
S=$(date +%s.%N)
$D -e "SELECT COUNT(*), ROUND(SUM(amount)) FROM t_part_month WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null >/dev/null
E=$(date +%s.%N)
printf '  %.3f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "=========== 实验 4：分桶裁剪（等值查询命中单个桶）==========="
echo "查询：按 user_id 精确查（user_id 是分桶键）"

echo "--- 不分区表：user_id 是分桶键，应命中 1 个桶 ---"
$D -e "EXPLAIN SELECT COUNT(*) FROM t_nopart_user WHERE user_id = 12345;" 2>/dev/null | grep -iE "tablets=|cardinality=" | head -4

echo "--- 分区表：每个分区都要查 1 个桶 → tablets = 分区数 × 1 ---"
$D -e "EXPLAIN SELECT COUNT(*) FROM t_part_month WHERE user_id = 12345;" 2>/dev/null | grep -iE "tablets=|cardinality=" | head -4

echo ""
echo "=========== 实验 5：分区裁剪 + 分桶裁剪同时生效 ============"
echo "查询：2025年6月 + 指定 user_id"
$D -e "EXPLAIN SELECT COUNT(*) FROM t_part_month WHERE user_id = 12345 AND order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "tablets=|cardinality=" | head -4

echo ""
echo "=========== 实验 6：结果正确性校验（分区表 vs 不分区表必须一致）==========="
echo "--- 不分区表 ---"
$D -e "SELECT COUNT(*) AS cnt, ROUND(SUM(amount)) AS total FROM t_nopart_user WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- 分区表 ---"
$D -e "SELECT COUNT(*) AS cnt, ROUND(SUM(amount)) AS total FROM t_part_month WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "BENCH4_DONE"

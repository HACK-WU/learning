#!/bin/bash
# 第一课实测：在 MySQL（行存）上跑分析型查询，记录真实耗时
# 运行方式：wsl -d Ubuntu -- bash /tmp/l01/bench.sh

MYSQL="docker exec doris-mysql-demo mysql -uroot -proot123 shop -t"

run_sql () {
  local label="$1"
  local sql="$2"
  local start end
  start=$(date +%s.%N)
  $MYSQL -e "$sql" 2>/dev/null
  end=$(date +%s.%N)
  printf '\n>>> %s 耗时: %.2f 秒\n' "$label" "$(echo "$end - $start" | bc)"
}

echo "================ 数据规模 ================"
$MYSQL -e "SELECT COUNT(*) AS total_rows FROM orders;" 2>/dev/null

echo ""
echo "================ Q1: 全表聚合（只读 amount 一列） ================"
$MYSQL -e "EXPLAIN SELECT COUNT(*) c, ROUND(SUM(amount)) total_amount FROM orders;" 2>/dev/null
run_sql "Q1 全表 SUM(amount)" "SELECT COUNT(*) c, ROUND(SUM(amount)) total_amount FROM orders;"

echo ""
echo "================ Q2: 分组聚合（故事里的核心场景） ================"
$MYSQL -e "EXPLAIN SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null
run_sql "Q2 GROUP BY province" "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;"

echo ""
echo "================ Q3: 点查（OLTP 的主场，对照组） ================"
run_sql "Q3 主键点查" "SELECT * FROM orders WHERE id = 12345678;"

echo ""
echo "================ Q4: 带时间索引的范围聚合 ================"
run_sql "Q4 近一个月按省汇总" \
  "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders WHERE order_date >= '2025-12-01' AND order_date < '2026-01-01' GROUP BY province ORDER BY total DESC;"

echo ""
echo "================ 关键指标：Q2 到底扫了多少数据 ================"
$MYSQL -e "SELECT ROUND(data_length/1024/1024) AS 整表数据_MB, ROUND(index_length/1024/1024) AS 索引_MB, ROUND((data_length+index_length)/1024/1024) AS 合计_MB, table_rows AS 行数 FROM information_schema.tables WHERE table_schema='shop' AND table_name='orders';" 2>/dev/null

echo ""
echo "================ Q2 实际需要用到的数据量估算 ================"
$MYSQL -e "
SELECT
  COUNT(DISTINCT province) AS province_字节级基数,
  ROUND(SUM(amount))      AS 只需这一个数值
FROM orders;" 2>/dev/null

echo ""
echo "================ InnoDB 页级读取统计（重跑前后差值） ================"
$MYSQL -e "SHOW STATUS LIKE 'Innodb_data_reads';" 2>/dev/null
$MYSQL -e "SELECT province, COUNT(*) c, ROUND(SUM(amount)) total FROM orders GROUP BY province ORDER BY total DESC;" 2>/dev/null > /dev/null
$MYSQL -e "SHOW STATUS LIKE 'Innodb_data_reads';" 2>/dev/null
$MYSQL -e "SHOW STATUS LIKE 'Innodb_buffer_pool_reads';" 2>/dev/null
$MYSQL -e "SHOW STATUS LIKE 'Innodb_rows_read';" 2>/dev/null

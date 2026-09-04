#!/bin/bash
# 课 8 实验 12：分区增量刷新（用 MV 自己的分区名）
# 已知：MV 的分区名由系统自动生成（p_20250101_20250201），不能用基表的 p202501
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 1. 分区 MV 的分区验证 =========="
echo "--- 1a: MV 的分区 ---"
runq "SHOW PARTITIONS FROM mv_part_daily;" | awk -F'\t' '{print $2, $12, $21}'
echo "--- 1b: 基表的分区 ---"
runq "SHOW PARTITIONS FROM orders_part;" | awk -F'\t' '{print $2, $12, $21}'
echo "--- 1c: 两边数据一致性 ---"
runq "SELECT COUNT(*) AS mv_rows, SUM(cnt) AS mv_sum FROM mv_part_daily;"
runq "SELECT COUNT(*) AS base_rows FROM orders_part;"

echo ""
echo "========== 2. 只刷一个分区（增量刷新）=========="
echo "--- 2a: 记录刷新前的版本 ---"
runq "SHOW PARTITIONS FROM mv_part_daily;" | awk -F'\t' '{print $2, $3}'
echo "--- 2b: 只刷 p_20250101_20250201 ---"
runq "REFRESH MATERIALIZED VIEW mv_part_daily PARTITION (p_20250101_20250201);"
echo "--- 2c: 刷新后版本（只有目标分区版本应该 +1）---"
runq "SHOW PARTITIONS FROM mv_part_daily;" | awk -F'\t' '{print $2, $3}'

echo ""
echo "========== 3. 分区增量的价值验证：只改一个分区的数据 =========="
echo "--- 3a: 往 p202501 分区插入新数据 ---"
runq "INSERT INTO orders_part VALUES
  ('2025-01-15','广东',8888888,500.00),
  ('2025-01-16','广东',8888889,600.00);"
runq "SELECT COUNT(*) AS base_rows FROM orders_part;"
echo "--- 3b: 此时 MV 还是旧值 ---"
runq "SELECT COUNT(*) AS mv_rows, SUM(cnt) AS mv_sum FROM mv_part_daily;"
echo "--- 3c: 只刷受影响的分区 ---"
runq "REFRESH MATERIALIZED VIEW mv_part_daily PARTITION (p_20250101_20250201);"
echo "    （异步执行，等 10 秒）"
sleep 10
runq "SELECT COUNT(*) AS mv_rows, SUM(cnt) AS mv_sum FROM mv_part_daily;"
echo "--- 3d: 对照：另一个分区没动 ---"
runq "SELECT order_date, SUM(cnt) AS c FROM mv_part_daily WHERE order_date >= '2025-02-01' GROUP BY order_date ORDER BY order_date LIMIT 3;"

echo ""
echo "========== 4. 全量刷新（COMPLETE）对照 =========="
runq "REFRESH MATERIALIZED VIEW mv_part_daily COMPLETE;"
sleep 10
runq "SELECT COUNT(*) AS mv_rows, SUM(cnt) AS mv_sum FROM mv_part_daily;"
runq "SELECT COUNT(*) AS base_rows FROM orders_part;"

echo ""
echo "========== 5. 定时刷新（ON SCHEDULE）=========="
echo "--- 5a: 建一个定时刷新的 MV ---"
runq "DROP MATERIALIZED VIEW IF EXISTS mv_sched;"
runq "CREATE MATERIALIZED VIEW mv_sched
BUILD IMMEDIATE REFRESH COMPLETE ON SCHEDULE EVERY 1 MINUTE
DISTRIBUTED BY HASH(province) BUCKETS 2
AS
SELECT province, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders_part
GROUP BY province;"
runq "SELECT COUNT(*) AS mv_sched_rows FROM mv_sched;"
echo "--- 5b: 看它的定义（确认定时策略写进去了）---"
runq "SHOW CREATE MATERIALIZED VIEW mv_sched;" | head -3

echo ""
echo "========== 6. 清理测试数据 =========="
runq "DELETE FROM orders_part WHERE user_id IN (8888888, 8888889);"
runq "SELECT COUNT(*) AS base_rows FROM orders_part;"

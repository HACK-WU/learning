#!/bin/bash
# 课 8 实验 11：MV 刷新方式对比 + 分区增量刷新 + 耗时对照
# 已知：REFRESH COMPLETE 是异步提交，返回后立刻查可能读到旧值（lab10 踩过）
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 2
echo "--- 清理测试数据 ---"
runq "DELETE FROM orders WHERE user_id = 9999999;"
runq "SELECT COUNT(*) AS base_cnt FROM orders;"

echo ""
echo "========== 1. 耗时对照：查基表 vs 查 MV（同一业务问题）=========="
echo "--- 1a: 查基表（2150 万行全表聚合）---"
for i in 1 2 3 4; do
  runq "SELECT province, SUM(amount) AS total FROM orders GROUP BY province ORDER BY province;" > /dev/null
done
echo "--- 1b: 查 MV（23360 行）---"
for i in 1 2 3 4; do
  runq "SELECT province, SUM(total_amount) AS total FROM mv_prov_pay_daily GROUP BY province ORDER BY province;" > /dev/null
done

echo ""
echo "========== 2. 从 Profile 取耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "mv_prov_pay_daily|FROM orders GROUP BY province" | tail -8

echo ""
echo "========== 3. 透明改写后的实际耗时（查基表，但被改写到 MV）=========="
echo "--- 3a: 查基表 orders（应被透明改写命中 MV）---"
for i in 1 2 3 4; do
  runq "SELECT order_date, province, pay_type, COUNT(*) AS c, SUM(amount) AS s FROM orders GROUP BY order_date, province, pay_type;" > /dev/null
done
echo "--- 确认改写确实发生 ---"
runq "EXPLAIN SELECT order_date, province, pay_type, COUNT(*) AS c, SUM(amount) AS s FROM orders GROUP BY order_date, province, pay_type;" | grep -E "TABLE:|RewriteSuccessAndChose" 
echo "--- 从 Profile 取改写后的耗时 ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "GROUP BY order_date, province, pay_type" | tail -4

echo ""
echo "========== 4. 刷新方式：COMPLETE（全量）vs AUTO（智能判断）=========="
echo "--- 4a: REFRESH AUTO（无数据变化时应该跳过）---"
date +"    提交前: %H:%M:%S"
runq "REFRESH MATERIALIZED VIEW mv_prov_pay_daily AUTO;"
date +"    提交后: %H:%M:%S"
echo "--- 4b: REFRESH COMPLETE（全量重算）---"
runq "REFRESH MATERIALIZED VIEW mv_prov_pay_daily COMPLETE;"
echo "    （异步执行，等 15 秒后校验）"
sleep 15
runq "SELECT COUNT(*) AS mv_rows, SUM(order_cnt) AS mv_sum FROM mv_prov_pay_daily;"
runq "SELECT COUNT(*) AS base_cnt FROM orders;"

echo ""
echo "========== 5. 分区增量刷新（基表必须是分区表）=========="
echo "--- 5a: 建一张分区基表 ---"
runq "DROP TABLE IF EXISTS orders_part;"
runq "CREATE TABLE orders_part (
  order_date DATE NOT NULL,
  province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(order_date, province)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES ('replication_num' = '1');"
runq "ALTER TABLE orders_part ADD PARTITION p202501 VALUES [('2025-01-01'), ('2025-02-01'));"
runq "ALTER TABLE orders_part ADD PARTITION p202502 VALUES [('2025-02-01'), ('2025-03-01'));"
runq "INSERT INTO orders_part SELECT order_date, province, user_id, amount FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2025-03-01' LIMIT 500000;"
runq "SELECT COUNT(*) AS part_rows FROM orders_part;"
runq "SHOW PARTITIONS FROM orders_part;" | head -6

echo ""
echo "--- 5b: 在分区表上建 MV（分区增量刷新）---"
runq "DROP MATERIALIZED VIEW IF EXISTS mv_part_daily;"
runq "CREATE MATERIALIZED VIEW mv_part_daily
BUILD IMMEDIATE REFRESH AUTO ON MANUAL
PARTITION BY (order_date)
DISTRIBUTED BY HASH(province) BUCKETS 4
AS
SELECT order_date, province, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders_part
GROUP BY order_date, province;"
runq "SELECT COUNT(*) AS mv_part_rows FROM mv_part_daily;"

echo ""
echo "--- 5c: 分区增量刷新：只刷一个分区 ---"
runq "REFRESH MATERIALIZED VIEW mv_part_daily PARTITION (p202501);"
runq "SELECT COUNT(*) AS mv_part_rows FROM mv_part_daily;"

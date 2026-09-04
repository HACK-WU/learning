#!/bin/bash
# 课 8 实验 10：异步物化视图与透明改写
# 关键：先删掉探测阶段建的 mv_probe，避免它干扰改写判定
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 清理探测阶段的 mv_probe =========="
runq "DROP MATERIALIZED VIEW IF EXISTS mv_probe;"
runq "SHOW TABLES;" | grep -E "mv_|probe"

echo ""
echo "========== 1. 建一个业务场景的异步 MV =========="
echo "--- 场景：每天按「省 + 支付方式」汇总销售额，报表反复查 ---"
runq "DROP MATERIALIZED VIEW IF EXISTS mv_prov_pay_daily;"
runq "CREATE MATERIALIZED VIEW mv_prov_pay_daily
BUILD IMMEDIATE REFRESH AUTO ON MANUAL
DISTRIBUTED BY HASH(province) BUCKETS 4
AS
SELECT
  order_date,
  province,
  pay_type,
  COUNT(*) AS order_cnt,
  SUM(amount) AS total_amount
FROM orders
GROUP BY order_date, province, pay_type;"

echo ""
echo "========== 2. 验证 MV 已建且有数据 =========="
runq "SELECT COUNT(*) AS mv_rows FROM mv_prov_pay_daily;"
runq "SELECT * FROM mv_prov_pay_daily ORDER BY order_date, province, pay_type LIMIT 6;"

echo ""
echo "========== 3. 对比：基表直接查 vs 走 MV =========="
echo "--- 3a: 基表直接查（origin）---"
for i in 1 2 3; do
  runq "SELECT order_date, province, pay_type, COUNT(*) AS order_cnt, SUM(amount) AS total_amount FROM orders GROUP BY order_date, province, pay_type ORDER BY order_date, province, pay_type;" > /dev/null
done
echo "--- 3b: 直接查 MV ---"
for i in 1 2 3; do
  runq "SELECT order_date, province, pay_type, order_cnt, total_amount FROM mv_prov_pay_daily ORDER BY order_date, province, pay_type;" > /dev/null
done

echo ""
echo "========== 4. 从 Profile 取二者耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "mv_prov_pay_daily|GROUP BY order_date" | tail -8

echo ""
echo "========== 5. 透明改写：查基表，看是否被改写到 MV =========="
echo "--- 5a: 与 MV 定义完全一致的查询 ---"
runq "EXPLAIN SELECT order_date, province, pay_type, COUNT(*) AS order_cnt, SUM(amount) AS total_amount FROM orders GROUP BY order_date, province, pay_type;" | grep -E "TABLE:|RewriteSuccess|RewriteFail"

echo ""
echo "--- 5b: 只取部分聚合列 ---"
runq "EXPLAIN SELECT province, SUM(amount) AS total_amount FROM orders GROUP BY province;" | grep -E "TABLE:|RewriteSuccess|RewriteFail"

echo ""
echo "--- 5c: 带 WHERE 过滤（MV 里有 order_date，能下推）---"
runq "EXPLAIN SELECT province, SUM(amount) AS total_amount FROM orders WHERE order_date = '2026-01-01' GROUP BY province;" | grep -E "TABLE:|RewriteSuccess|RewriteFail|PREDICATES"

echo ""
echo "--- 5d: 明细查询（MV 只有聚合结果，不支持明细，应该不命中）---"
runq "EXPLAIN SELECT order_date, province, amount FROM orders WHERE amount > 4000 LIMIT 10;" | grep -E "TABLE:|RewriteSuccess|RewriteFail"

echo ""
echo "========== 6. 关闭改写开关做对照 =========="
runq "SET enable_materialized_view_rewrite = false;"
runq "EXPLAIN SELECT province, SUM(amount) AS total_amount FROM orders GROUP BY province;" | grep -E "TABLE:|RewriteSuccess|RewriteFail"
runq "SET enable_materialized_view_rewrite = true;"
runq "EXPLAIN SELECT province, SUM(amount) AS total_amount FROM orders GROUP BY province;" | grep -E "TABLE:|RewriteSuccess|RewriteFail"

echo ""
echo "========== 7. 刷新机制验证：基表新增数据后，MV 是否自动跟上 =========="
echo "--- 7a: 记录当前 MV 数据 ---"
runq "SELECT COUNT(*) AS mv_rows, SUM(order_cnt) AS mv_total_cnt FROM mv_prov_pay_daily;"
echo "--- 7b: 基表插入新数据 ---"
runq "INSERT INTO orders VALUES
  ('2026-01-01','广东','深圳',9999999,1,'测试',1,1.00,'支付宝',1,'test',NOW(),NOW());"
echo "--- 7c: 立刻查 MV（ON MANUAL 手动刷新，此时应该还是旧值）---"
runq "SELECT SUM(order_cnt) AS mv_total_cnt FROM mv_prov_pay_daily;"
echo "--- 7d: 基表直接聚合（应该是新值）---"
runq "SELECT COUNT(*) AS base_total_cnt FROM orders;"
echo "--- 7e: 手动刷新 MV ---"
runq "REFRESH MATERIALIZED VIEW mv_prov_pay_daily COMPLETE;"
echo "--- 7f: 刷新后再查 MV ---"
runq "SELECT SUM(order_cnt) AS mv_total_cnt FROM mv_prov_pay_daily;"

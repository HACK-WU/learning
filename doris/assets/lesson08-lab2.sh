#!/bin/bash
# 课 8 实验 2（修正版）：建干净的维表 + 用真实耗时数据说话
# 发现：perf_wide 的 province 是另一套地名（与 orders 零交集），不能用来做 Join 实验。
#       改用从 orders 派生的事实表，保证 join 键有真实交集。
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置确认 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 3
runq "SHOW VARIABLES LIKE 'enable_sql_cache';"

echo ""
echo "========== 1. 建一张干净的 Join 实验维表（province 与 orders 完全同源）=========="
runq "DROP TABLE IF EXISTS dim_region;"
runq "CREATE TABLE dim_region (
  province VARCHAR(16) NOT NULL,
  region VARCHAR(16) NOT NULL,
  level VARCHAR(8) NOT NULL DEFAULT 'A'
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 2
PROPERTIES ('replication_num' = '1');"

runq "INSERT INTO dim_region
SELECT province,
       CASE province
         WHEN '广东' THEN '华南' WHEN '广西' THEN '华南' WHEN '福建' THEN '华南'
         WHEN '江苏' THEN '华东' WHEN '浙江' THEN '华东' WHEN '山东' THEN '华东'
         WHEN '上海' THEN '华东'
         WHEN '河南' THEN '华中' WHEN '湖北' THEN '华中'
         WHEN '四川' THEN '西南'
         ELSE '其他' END AS region,
       'A' AS level
FROM orders GROUP BY province;"
runq "SELECT COUNT(*) AS dim_rows FROM dim_region;"
runq "SELECT * FROM dim_region ORDER BY province;"

echo ""
echo "========== 2. 确认 join 键有真实交集 =========="
runq "SELECT COUNT(*) AS matched FROM (SELECT DISTINCT province FROM dim_region) d JOIN (SELECT DISTINCT province FROM orders) o ON d.province = o.province;"

echo ""
echo "========== 3. 建一张中表（200 万行，province 与 orders 同源）=========="
runq "DROP TABLE IF EXISTS mid_orders;"
runq "CREATE TABLE mid_orders (
  province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ('replication_num' = '1');"
date +"    开始灌数: %H:%M:%S"
runq "INSERT INTO mid_orders SELECT province, user_id, amount FROM orders LIMIT 2000000;"
date +"    结束灌数: %H:%M:%S"
runq "SELECT COUNT(*) AS mid_rows FROM mid_orders;"
runq "ANALYZE TABLE mid_orders WITH SYNC;"
runq "ANALYZE TABLE dim_region WITH SYNC;"

echo ""
echo "========== 4. 四类 Join 的真实耗时（每组跑 3 次取范围）=========="
echo ""
echo "--- 4a: 单表聚合（基线，不 Join）---"
for i in 1 2 3; do
  runq "SELECT province, COUNT(*) AS cnt, SUM(amount) AS amt FROM orders GROUP BY province ORDER BY province;" > /dev/null
done
echo "    （耗时见下方 Profile 汇总）"

echo ""
echo "--- 4b: 大表 JOIN 小表（orders 2150万 JOIN dim_region 8行）---"
for i in 1 2 3; do
  runq "SELECT o.province, d.region, COUNT(*) AS cnt, SUM(o.amount) AS amt FROM orders o JOIN dim_region d ON o.province = d.province GROUP BY o.province, d.region ORDER BY o.province;" | head -3
done

echo ""
echo "--- 4c: 大表 JOIN 中表（orders 2150万 JOIN mid_orders 200万，分桶键）---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM orders o JOIN mid_orders m ON o.province = m.province;"
done

echo ""
echo "--- 4d: 大表 JOIN 大表（orders 2150万 JOIN orders_dup 2050万，非分桶键）---"
for i in 1 2; do
  runq "SELECT COUNT(*) AS total FROM orders o JOIN orders_dup p ON o.user_id = p.user_id;"
done

echo ""
echo "--- 4e: Colocate Join（orders JOIN fact_prov，同组同分桶键）---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM orders o JOIN fact_prov f ON o.province = f.province;"
done

echo ""
echo "========== 5. 从 Profile 里取这几次查询的真实耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "dim_region|mid_orders|orders_dup|fact_prov|GROUP BY province" | tail -20

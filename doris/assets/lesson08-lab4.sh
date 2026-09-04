#!/bin/bash
# 课 8 实验 4：能在单机跑完的 Join 规模
# 教训：orders 2150 万行 JOIN 任何上百万行的表，中间结果爆炸，单机跑不完。
#       → 用可控规模：把 orders 缩小成一个子集表（100 万行），再做 Join 对比。
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
runq "SHOW VARIABLES LIKE 'query_timeout';"
sleep 2

echo ""
echo "========== 1. 建实验子集表（100 万行，province 8 个）=========="
runq "DROP TABLE IF EXISTS fact_1m;"
runq "CREATE TABLE fact_1m (
  order_date DATE NOT NULL,
  province VARCHAR(16) NOT NULL,
  city VARCHAR(32) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO fact_1m SELECT order_date, province, city, user_id, amount FROM orders LIMIT 1000000;"
runq "SELECT COUNT(*) AS fact_1m_rows FROM fact_1m;"

echo ""
echo "========== 2. 建三档维表（小/中/大），都按 province 分布 =========="
runq "DROP TABLE IF EXISTS dim_small;"
runq "CREATE TABLE dim_small (province VARCHAR(16) NOT NULL, region VARCHAR(16) NOT NULL)
DUPLICATE KEY(province) DISTRIBUTED BY HASH(province) BUCKETS 2 PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO dim_small SELECT province, region FROM dim_region;"

runq "DROP TABLE IF EXISTS dim_mid;"
runq "CREATE TABLE dim_mid (province VARCHAR(16) NOT NULL, user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL)
DUPLICATE KEY(province) DISTRIBUTED BY HASH(province) BUCKETS 8 PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO dim_mid SELECT province, user_id, amount FROM fact_1m LIMIT 100000;"
runq "SELECT COUNT(*) AS dim_mid_rows FROM dim_mid;"

runq "ANALYZE TABLE fact_1m WITH SYNC;"
runq "ANALYZE TABLE dim_small WITH SYNC;"
runq "ANALYZE TABLE dim_mid WITH SYNC;"

echo ""
echo "========== 3. 三档 Join 的 EXPLAIN 策略 =========="
echo "--- 3a: fact_1m JOIN dim_small（8 行）---"
runq "EXPLAIN SELECT o.province, d.region, COUNT(*) AS cnt FROM fact_1m o JOIN dim_small d ON o.province = d.province GROUP BY o.province, d.region;" | grep -E "join op"
echo "--- 3b: fact_1m JOIN dim_mid（10 万行，分桶键）---"
runq "EXPLAIN SELECT o.province, COUNT(*) AS cnt FROM fact_1m o JOIN dim_mid m ON o.province = m.province GROUP BY o.province;" | grep -E "join op"
echo "--- 3c: fact_1m JOIN dim_mid（10 万行，非分桶键 user_id）---"
runq "EXPLAIN SELECT COUNT(*) AS total FROM fact_1m o JOIN dim_mid m ON o.user_id = m.user_id;" | grep -E "join op"
echo "--- 3d: fact_1m 自连接（100万 JOIN 100万，分桶键）---"
runq "EXPLAIN SELECT COUNT(*) AS total FROM fact_1m a JOIN fact_1m b ON a.province = b.province;" | grep -E "join op"

echo ""
echo "========== 4. 真实耗时（每组 3 次）=========="
echo "--- 4a: 单表聚合基线 ---"
for i in 1 2 3; do
  runq "SELECT province, COUNT(*) AS cnt, SUM(amount) AS amt FROM fact_1m GROUP BY province ORDER BY province;" > /dev/null
done
echo "--- 4b: JOIN 小维表 8 行 ---"
for i in 1 2 3; do
  runq "SELECT o.province, d.region, COUNT(*) AS cnt FROM fact_1m o JOIN dim_small d ON o.province = d.province GROUP BY o.province, d.region ORDER BY o.province;" > /dev/null
done
echo "--- 4c: JOIN 中表 10 万行（分桶键 → BUCKET_SHUFFLE）---"
for i in 1 2 3; do
  runq "SELECT o.province, COUNT(*) AS cnt FROM fact_1m o JOIN dim_mid m ON o.province = m.province GROUP BY o.province ORDER BY o.province;" > /dev/null
done
echo "--- 4d: JOIN 中表 10 万行（非分桶键 → SHUFFLE）---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM fact_1m o JOIN dim_mid m ON o.user_id = m.user_id;" > /dev/null
done

echo ""
echo "========== 5. 从 Profile 取真实耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "dim_small|dim_mid|fact_1m" | tail -20

#!/bin/bash
# 课 8 实验 3：Join 耗时测量（修正方法）
# 教训 1：大表 JOIN 中表（8 亿+ 中间结果）跑不完，会触发默认 300s 查询超时。
#          → 改用 Profile 里的 Total 时间，不等它跑完。
# 教训 2：不能拿「跑不完」当结论，要换成能跑完的规模再测。
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 2

echo ""
echo "========== 1. 控制规模：建一张小一点的中表（20 万行）=========="
runq "DROP TABLE IF EXISTS mid_small;"
runq "CREATE TABLE mid_small (
  province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO mid_small SELECT province, user_id, amount FROM orders LIMIT 200000;"
runq "SELECT COUNT(*) AS mid_small_rows FROM mid_small;"
runq "ANALYZE TABLE mid_small WITH SYNC;"

echo ""
echo "========== 2. 用 EXPLAIN 看每种 Join 的执行策略（确定性证据）=========="
echo "--- 2a: 小维表 8 行 ---"
runq "EXPLAIN SELECT o.province, d.region, COUNT(*) FROM orders o JOIN dim_region d ON o.province = d.province GROUP BY o.province, d.region;" | grep -E "join op|TABLE:"
echo "--- 2b: 中表 20 万行，分桶键 join ---"
runq "EXPLAIN SELECT COUNT(*) FROM orders o JOIN mid_small m ON o.province = m.province;" | grep -E "join op|TABLE:"
echo "--- 2c: 中表 20 万行，非分桶键 join ---"
runq "EXPLAIN SELECT COUNT(*) FROM orders o JOIN mid_small m ON o.user_id = m.user_id;" | grep -E "join op|TABLE:"
echo "--- 2d: colocate 表，分桶键 join ---"
runq "EXPLAIN SELECT COUNT(*) FROM orders o JOIN fact_prov f ON o.province = f.province;" | grep -E "join op|TABLE:"

echo ""
echo "========== 3. 能跑完的三组 Join，测真实耗时 =========="
echo "--- 3a: 大表 JOIN 小维表（8 行）---"
for i in 1 2 3; do
  runq "SELECT o.province, d.region, COUNT(*) AS cnt, SUM(o.amount) AS amt FROM orders o JOIN dim_region d ON o.province = d.province GROUP BY o.province, d.region ORDER BY o.province;" > /dev/null
done

echo "--- 3b: 大表 JOIN 中表（20 万行，分桶键）---"
for i in 1 2 3; do
  runq "SELECT o.province, m.province, COUNT(*) AS cnt FROM orders o JOIN mid_small m ON o.province = m.province GROUP BY o.province, m.province ORDER BY o.province;" > /dev/null
done

echo "--- 3c: 大表 JOIN 中表（20 万行，非分桶键 → SHUFFLE）---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM orders o JOIN mid_small m ON o.user_id = m.user_id;" > /dev/null
done

echo "--- 3d: Colocate Join（orders JOIN fact_prov 200万行，分桶键）---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM orders o JOIN fact_prov f ON o.province = f.province;" > /dev/null
done

echo ""
echo "========== 4. 从 Profile 取这几次查询的真实耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "dim_region|mid_small|fact_prov" | tail -16

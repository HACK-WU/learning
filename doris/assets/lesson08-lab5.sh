#!/bin/bash
# 课 8 实验 5：公平对照——只改 Join 键，其他全一样
# 教训（lab4 踩的坑）：拿 province join（156 亿行中间结果）和 user_id join（24.5 万行）比耗时，
#                    比的是「中间结果规模」，不是「Join 策略」。这是无效对比。
# 正确做法：控制中间结果规模一致，只让优化器换策略。
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 2

echo ""
echo "========== 1. 建两张结构相同、只有分桶键不同的维表 =========="
echo "--- colo_dim：与 fact_1m 同分桶键(province)、同 8 桶、同 colocate group ---"
runq "DROP TABLE IF EXISTS colo_dim;"
runq "CREATE TABLE colo_dim (
  province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ('replication_num' = '1', 'colocate_with' = 'prov_group');"
runq "INSERT INTO colo_dim SELECT province, user_id, amount FROM fact_1m LIMIT 100000;"

echo "--- non_colo_dim：同样是 10 万行，但不在 colocate group ---"
runq "DROP TABLE IF EXISTS non_colo_dim;"
runq "CREATE TABLE non_colo_dim (
  province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO non_colo_dim SELECT province, user_id, amount FROM fact_1m LIMIT 100000;"

runq "SELECT COUNT(*) AS colo_rows FROM colo_dim;"
runq "SELECT COUNT(*) AS non_colo_rows FROM non_colo_dim;"
runq "ANALYZE TABLE colo_dim WITH SYNC;"
runq "ANALYZE TABLE non_colo_dim WITH SYNC;"

echo ""
echo "========== 2. Colocate 开关对照（同一条 SQL，只改一个变量）=========="
echo "--- 2a: 开 colocate（默认），fact_1m JOIN colo_dim ON province ---"
runq "EXPLAIN SELECT COUNT(*) AS total FROM fact_1m o JOIN colo_dim d ON o.province = d.province;" | grep -E "join op|cardinality=1[0-9]"
echo "--- 2b: 关 colocate（disable_colocate_plan=true），同一条 SQL ---"
runq "SET disable_colocate_plan = true; EXPLAIN SELECT COUNT(*) AS total FROM fact_1m o JOIN colo_dim d ON o.province = d.province;" | grep -E "join op|cardinality=1[0-9]"
echo "--- 2c: 与非 colocate 表 join（结构上等价，但不在组里）---"
runq "EXPLAIN SELECT COUNT(*) AS total FROM fact_1m o JOIN non_colo_dim d ON o.province = d.province;" | grep -E "join op|cardinality=1[0-9]"

echo ""
echo "========== 3. 控制中间结果规模（用 user_id 做 join 键，规模稳定在 24 万行）=========="
echo "--- 3a: 非 colocate 表，user_id join ---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM fact_1m o JOIN non_colo_dim d ON o.user_id = d.user_id;" > /dev/null
done
echo "--- 3b: colocate 表，user_id join（user_id 不是分桶键，colocate 不生效）---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM fact_1m o JOIN colo_dim d ON o.user_id = d.user_id;" > /dev/null
done

echo ""
echo "========== 4. Runtime Filter 开关对照（同一条 SQL，只改 RF 模式）=========="
echo "--- 4a: 开 RF（默认 GLOBAL），带过滤条件 ---"
runq "EXPLAIN SELECT COUNT(*) AS total FROM fact_1m o JOIN non_colo_dim d ON o.user_id = d.user_id WHERE d.amount > 4000;" | grep -E "runtime filters|join op"
echo "--- 4b: 关 RF（runtime_filter_mode=OFF）---"
runq "SET runtime_filter_mode = OFF; EXPLAIN SELECT COUNT(*) AS total FROM fact_1m o JOIN non_colo_dim d ON o.user_id = d.user_id WHERE d.amount > 4000;" | grep -E "runtime filters|join op"

echo ""
echo "========== 5. RF 效果实测（带过滤 vs 不带过滤，看扫描行数）=========="
echo "--- 5a: 不带过滤 ---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM fact_1m o JOIN non_colo_dim d ON o.user_id = d.user_id;" > /dev/null
done
echo "--- 5b: 带过滤（d.amount > 4000，RF 应能提前过滤左表）---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS total FROM fact_1m o JOIN non_colo_dim d ON o.user_id = d.user_id WHERE d.amount > 4000;" > /dev/null
done
echo "--- 5c: 关 RF 后带过滤（对照）---"
for i in 1 2 3; do
  runq "SET runtime_filter_mode = OFF; SELECT COUNT(*) AS total FROM fact_1m o JOIN non_colo_dim d ON o.user_id = d.user_id WHERE d.amount > 4000;" > /dev/null
done

echo ""
echo "========== 6. 从 Profile 取真实耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "colo_dim|non_colo_dim" | tail -20

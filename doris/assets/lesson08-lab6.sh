#!/bin/bash
# 课 8 实验 6：VARIANT vs JSON 字符串 vs 结构化列（性能与写法对比）
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 2

echo ""
echo "========== 1. 建三张表：VARIANT / JSON字符串 / 结构化列 =========="
echo "--- 1a: VARIANT 表 ---"
runq "DROP TABLE IF EXISTS log_variant;"
runq "CREATE TABLE log_variant (
  ts DATETIME NOT NULL,
  uid BIGINT NOT NULL,
  payload VARIANT NULL
)
DUPLICATE KEY(ts, uid)
DISTRIBUTED BY HASH(uid) BUCKETS 4
PROPERTIES ('replication_num' = '1');"

echo "--- 1b: JSON 字符串表（传统做法）---"
runq "DROP TABLE IF EXISTS log_json;"
runq "CREATE TABLE log_json (
  ts DATETIME NOT NULL,
  uid BIGINT NOT NULL,
  payload STRING NULL
)
DUPLICATE KEY(ts, uid)
DISTRIBUTED BY HASH(uid) BUCKETS 4
PROPERTIES ('replication_num' = '1');"

echo "--- 1c: 结构化列表（schema 固定时的做法）---"
runq "DROP TABLE IF EXISTS log_typed;"
runq "CREATE TABLE log_typed (
  ts DATETIME NOT NULL,
  uid BIGINT NOT NULL,
  city VARCHAR(32) NULL,
  device VARCHAR(16) NULL,
  cost INT NULL
)
DUPLICATE KEY(ts, uid)
DISTRIBUTED BY HASH(uid) BUCKETS 4
PROPERTIES ('replication_num' = '1');"

echo ""
echo "========== 2. 灌 100 万行同样的数据 =========="
echo "--- 2a: 先灌结构化表 ---"
date +"    开始: %H:%M:%S"
runq "INSERT INTO log_typed
SELECT
  DATE_ADD('2026-01-01 00:00:00', INTERVAL (user_id % 86400) SECOND) AS ts,
  user_id AS uid,
  province AS city,
  CASE user_id % 3 WHEN 0 THEN 'iOS' WHEN 1 THEN 'Android' ELSE 'Web' END AS device,
  CAST(user_id % 1000 AS INT) AS cost
FROM orders LIMIT 1000000;"
date +"    结束: %H:%M:%S"
runq "SELECT COUNT(*) AS typed_rows FROM log_typed;"

echo "--- 2b: 从结构化表生成 VARIANT 表 ---"
runq "INSERT INTO log_variant
SELECT ts, uid,
  CONCAT('{\"city\":\"', city, '\",\"device\":\"', device, '\",\"cost\":', CAST(cost AS STRING), '}') AS payload
FROM log_typed;"
runq "SELECT COUNT(*) AS variant_rows FROM log_variant;"

echo "--- 2c: 同样内容存成 JSON 字符串 ---"
runq "INSERT INTO log_json
SELECT ts, uid,
  CONCAT('{\"city\":\"', city, '\",\"device\":\"', device, '\",\"cost\":', CAST(cost AS STRING), '}') AS payload
FROM log_typed;"
runq "SELECT COUNT(*) AS json_rows FROM log_json;"

echo ""
echo "========== 3. 抽样看内容（确认三张表数据一致）=========="
runq "SELECT uid, payload FROM log_variant ORDER BY uid LIMIT 3;"
runq "SELECT uid, payload FROM log_json ORDER BY uid LIMIT 3;"
runq "SELECT uid, city, device, cost FROM log_typed ORDER BY uid LIMIT 3;"

echo ""
echo "========== 4. 三种写法查询同一业务问题：按城市统计 =========="
echo "--- 4a: 结构化列（最快，基线）---"
for i in 1 2 3; do
  runq "SELECT city, COUNT(*) AS cnt, SUM(cost) AS total FROM log_typed GROUP BY city ORDER BY city;" > /dev/null
done
echo "--- 4b: VARIANT 子列 ---"
for i in 1 2 3; do
  runq "SELECT payload['city'] AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY payload['city'] ORDER BY city;" > /dev/null
done
echo "--- 4c: JSON 字符串函数（最慢）---"
for i in 1 2 3; do
  runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt, SUM(CAST(get_json_string(payload, '\$.cost') AS BIGINT)) AS total FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;" > /dev/null
done

echo ""
echo "========== 5. 过滤场景：查某个设备的记录数 =========="
echo "--- 5a: 结构化列 ---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS cnt FROM log_typed WHERE device = 'iOS';" > /dev/null
done
echo "--- 5b: VARIANT 子列 ---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS cnt FROM log_variant WHERE payload['device'] = 'iOS';" > /dev/null
done
echo "--- 5c: JSON 字符串 ---"
for i in 1 2 3; do
  runq "SELECT COUNT(*) AS cnt FROM log_json WHERE get_json_string(payload, '\$.device') = 'iOS';" > /dev/null
done

echo ""
echo "========== 6. 从 Profile 取真实耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "log_variant|log_json|log_typed" | tail -22

echo ""
echo "========== 7. 三张表的磁盘占用对比 =========="
runq "SHOW DATA FROM log_variant;"
runq "SHOW DATA FROM log_json;"
runq "SHOW DATA FROM log_typed;"

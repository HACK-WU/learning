#!/bin/bash
# 课 8 实验 9：单独测聚合场景耗时（之前被过滤场景的 Profile 挤掉了）
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 2

echo ""
echo "========== 1. 聚合场景：结构化列（基线）=========="
for i in 1 2 3 4; do
  runq "SELECT city, COUNT(*) AS cnt, SUM(cost) AS total FROM log_typed GROUP BY city ORDER BY city;" > /dev/null
done
echo "--- 结构化列聚合耗时 ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_typed" | head -4

echo ""
echo "========== 2. 聚合场景：VARIANT 子列（CAST 后）=========="
for i in 1 2 3 4; do
  runq "SELECT CAST(payload['city'] AS VARCHAR(32)) AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY CAST(payload['city'] AS VARCHAR(32)) ORDER BY city;" > /dev/null
done
echo "--- VARIANT 聚合耗时 ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_variant" | head -4

echo ""
echo "========== 3. 聚合场景：JSON 字符串 =========="
for i in 1 2 3 4; do
  runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt, SUM(CAST(get_json_string(payload, '\$.cost') AS BIGINT)) AS total FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;" > /dev/null
done
echo "--- JSON 字符串聚合耗时 ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "log_json" | head -4

echo ""
echo "========== 4. 复杂类型：Array / Map / Struct 的用法验证 =========="
echo "--- 4a: 建表并插入 ---"
runq "DROP TABLE IF EXISTS user_profile;"
runq "CREATE TABLE user_profile (
  uid BIGINT NOT NULL,
  tags ARRAY<STRING> NULL,
  extra MAP<STRING,STRING> NULL,
  addr STRUCT<city:STRING,zip:STRING> NULL
)
DUPLICATE KEY(uid)
DISTRIBUTED BY HASH(uid) BUCKETS 2
PROPERTIES ('replication_num' = '1');"

runq "INSERT INTO user_profile VALUES
  (1001, ['vip','new'],      {'src':'app','ch':'a1'},  named_struct('city','深圳','zip','518000')),
  (1002, ['vip','old','big'],{'src':'web','ch':'b2'},  named_struct('city','北京','zip','100000')),
  (1003, ['new'],            {'src':'app','ch':'c3'},  named_struct('city','上海','zip','200000'));"

echo "--- 4b: 查全部 ---"
runq "SELECT uid, tags, extra, addr FROM user_profile ORDER BY uid;"

echo "--- 4c: 按下标取数组元素（注意：Doris 数组下标从 1 开始，[0] 返回 NULL）---"
runq "SELECT uid, tags[0] AS idx0, tags[1] AS idx1, tags[2] AS idx2 FROM user_profile ORDER BY uid;"

echo "--- 4d: 取 map 值 ---"
runq "SELECT uid, extra['src'] AS src, extra['ch'] AS ch FROM user_profile ORDER BY uid;"

echo "--- 4e: 取 struct 字段 ---"
runq "SELECT uid, addr.city AS city, addr.zip AS zip FROM user_profile ORDER BY uid;"

echo "--- 4f: 数组函数 ---"
runq "SELECT uid, size(tags) AS n, array_contains(tags,'vip') AS is_vip FROM user_profile ORDER BY uid;"

echo "--- 4g: 数组展开（explode，行转列）---"
runq "SELECT uid, tag FROM user_profile LATERAL VIEW explode(tags) t AS tag ORDER BY uid, tag;"

echo "--- 4h: 数组聚合 ---"
runq "SELECT array_agg(DISTINCT extra['src']) AS all_src FROM user_profile;"

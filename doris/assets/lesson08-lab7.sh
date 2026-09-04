#!/bin/bash
# 课 8 实验 7：补齐 VARIANT 实验的两块数据
# 1. 磁盘占用（SHOW DATA 依赖后台统计，紧跟 INSERT 会返回 0，课 7 实测需等约 45 秒）
# 2. 聚合场景耗时（lab6 只抓到过滤场景，聚合的 Profile 被挤掉了）
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 2

echo ""
echo "========== 1. 等统计刷新后查磁盘占用 =========="
echo "    （SHOW DATA 依赖后台统计，紧跟 INSERT 会返回 0。等 60 秒留余量）"
sleep 60
echo "--- log_typed（结构化列）---"
runq "SHOW DATA FROM log_typed;"
echo "--- log_variant（VARIANT）---"
runq "SHOW DATA FROM log_variant;"
echo "--- log_json（JSON 字符串）---"
runq "SHOW DATA FROM log_json;"

echo ""
echo "========== 2. 聚合场景耗时（每组 3 次）=========="
echo "--- 2a: 结构化列 ---"
runq "SELECT city, COUNT(*) AS cnt, SUM(cost) AS total FROM log_typed GROUP BY city ORDER BY city;" > /dev/null
runq "SELECT city, COUNT(*) AS cnt, SUM(cost) AS total FROM log_typed GROUP BY city ORDER BY city;" > /dev/null
runq "SELECT city, COUNT(*) AS cnt, SUM(cost) AS total FROM log_typed GROUP BY city ORDER BY city;" > /dev/null
echo "--- 2b: VARIANT 子列 ---"
runq "SELECT payload['city'] AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY payload['city'] ORDER BY city;" > /dev/null
runq "SELECT payload['city'] AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY payload['city'] ORDER BY city;" > /dev/null
runq "SELECT payload['city'] AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY payload['city'] ORDER BY city;" > /dev/null
echo "--- 2c: JSON 字符串 ---"
runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt, SUM(CAST(get_json_string(payload, '\$.cost') AS BIGINT)) AS total FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;" > /dev/null
runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt, SUM(CAST(get_json_string(payload, '\$.cost') AS BIGINT)) AS total FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;" > /dev/null
runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt, SUM(CAST(get_json_string(payload, '\$.cost') AS BIGINT)) AS total FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;" > /dev/null

echo ""
echo "========== 3. 确认三种写法结果一致（防止写法错误导致结果对不上）=========="
echo "--- 3a: 结构化列结果 ---"
runq "SELECT city, COUNT(*) AS cnt FROM log_typed GROUP BY city ORDER BY city;"
echo "--- 3b: VARIANT 结果 ---"
runq "SELECT payload['city'] AS city, COUNT(*) AS cnt FROM log_variant GROUP BY payload['city'] ORDER BY city;"
echo "--- 3c: JSON 字符串结果 ---"
runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;"

echo ""
echo "========== 4. 从 Profile 取聚合场景真实耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "log_variant|log_json|log_typed" | tail -12

echo ""
echo "========== 5. VARIANT 的子列提取（看它把 JSON 拆成了哪些列）=========="
runq "SHOW COLUMNS FROM log_variant;"
echo "--- 用 describe_extend_variant_column 看子列明细 ---"
runq "SET describe_extend_variant_column = true; DESC log_variant;"

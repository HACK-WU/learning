#!/bin/bash
# 课 8 实验 8：VARIANT 的正确用法（lab7 报错后的修正）
# 报错原文：variant column must use with specific function,
#          and don't support filter, group by or order by
# 关键：VARIANT 子列不能直接 GROUP BY / ORDER BY，必须先 CAST 成具体类型。
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 0. 前置 =========="
runq "SET GLOBAL enable_sql_cache = false;"
sleep 2

echo ""
echo "========== 1. 找 VARIANT 的官方用法说明 =========="
echo "help variant;" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password" | head -30

echo ""
echo "========== 2. 试各种 CAST 写法（聚合场景）=========="
echo "--- 2a: CAST(payload['city'] AS VARCHAR(32)) 后 GROUP BY ---"
runq "SELECT CAST(payload['city'] AS VARCHAR(32)) AS city, COUNT(*) AS cnt FROM log_variant GROUP BY CAST(payload['city'] AS VARCHAR(32)) ORDER BY city;" | head -10

echo ""
echo "--- 2b: 带 SUM 的聚合 ---"
runq "SELECT CAST(payload['city'] AS VARCHAR(32)) AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY CAST(payload['city'] AS VARCHAR(32)) ORDER BY city;" | head -10

echo ""
echo "========== 3. 过滤场景（lab6 已验证可用，这里复测确认）=========="
runq "SELECT COUNT(*) AS cnt FROM log_variant WHERE payload['device'] = 'iOS';"

echo ""
echo "========== 4. 三种写法聚合耗时对比（每组 4 次，取稳定值）=========="
echo "--- 4a: 结构化列 ---"
for i in 1 2 3 4; do
  runq "SELECT city, COUNT(*) AS cnt, SUM(cost) AS total FROM log_typed GROUP BY city ORDER BY city;" > /dev/null
done
echo "--- 4b: VARIANT 子列（CAST 后）---"
for i in 1 2 3 4; do
  runq "SELECT CAST(payload['city'] AS VARCHAR(32)) AS city, COUNT(*) AS cnt, SUM(CAST(payload['cost'] AS BIGINT)) AS total FROM log_variant GROUP BY CAST(payload['city'] AS VARCHAR(32)) ORDER BY city;" > /dev/null
done
echo "--- 4c: JSON 字符串 ---"
for i in 1 2 3 4; do
  runq "SELECT get_json_string(payload, '\$.city') AS city, COUNT(*) AS cnt, SUM(CAST(get_json_string(payload, '\$.cost') AS BIGINT)) AS total FROM log_json GROUP BY get_json_string(payload, '\$.city') ORDER BY city;" > /dev/null
done

echo ""
echo "========== 5. 三种写法过滤耗时对比（每组 4 次）=========="
echo "--- 5a: 结构化列 ---"
for i in 1 2 3 4; do
  runq "SELECT COUNT(*) AS cnt FROM log_typed WHERE device = 'iOS';" > /dev/null
done
echo "--- 5b: VARIANT 子列 ---"
for i in 1 2 3 4; do
  runq "SELECT COUNT(*) AS cnt FROM log_variant WHERE payload['device'] = 'iOS';" > /dev/null
done
echo "--- 5c: JSON 字符串 ---"
for i in 1 2 3 4; do
  runq "SELECT COUNT(*) AS cnt FROM log_json WHERE get_json_string(payload, '\$.device') = 'iOS';" > /dev/null
done

echo ""
echo "========== 6. 从 Profile 取真实耗时 =========="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep -E "log_variant|log_json|log_typed" | tail -26

echo ""
echo "========== 7. VARIANT 的动态 schema 能力（不同行不同字段）=========="
runq "TRUNCATE TABLE v_probe;"
runq "INSERT INTO v_probe VALUES
  (1, '{\"type\":\"login\",\"user\":\"alice\",\"ip\":\"1.2.3.4\"}'),
  (2, '{\"type\":\"pay\",\"user\":\"bob\",\"amount\":99.9,\"currency\":\"CNY\"}'),
  (3, '{\"type\":\"click\",\"user\":\"carol\",\"elem\":\"btn_buy\",\"page\":3}');"
runq "SELECT id, log['type'] AS type, log['user'] AS user FROM v_probe ORDER BY id;"
echo "--- 新字段自动成为子列（schema 变了也不用改表）---"
runq "SET describe_extend_variant_column = true; DESC v_probe;"

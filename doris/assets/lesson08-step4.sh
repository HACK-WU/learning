#!/bin/bash
# ============================================================
# 课 8 第四幕 步骤 4：VARIANT vs JSON 字符串（半结构化数据选型实测）
#
# 前提：已跑过 lesson08-setup.sh
#
# ⚠️ 本步骤会建 3 张 100 万行的表，耗时约 1 分钟
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 步骤 4.1：建三张表（同一份数据，三种存法）=========="

echo "--- 4.1a 结构化列（schema 固定时的做法）---"
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

echo "--- 4.1b VARIANT 列（字段不固定 / 经常变）---"
runq "DROP TABLE IF EXISTS log_variant;"
runq "CREATE TABLE log_variant (
  ts DATETIME NOT NULL,
  uid BIGINT NOT NULL,
  payload VARIANT NULL
)
DUPLICATE KEY(ts, uid)
DISTRIBUTED BY HASH(uid) BUCKETS 4
PROPERTIES ('replication_num' = '1');"

echo "--- 4.1c JSON 字符串（老做法，本课用来当反面教材）---"
runq "DROP TABLE IF EXISTS log_json;"
runq "CREATE TABLE log_json (
  ts DATETIME NOT NULL,
  uid BIGINT NOT NULL,
  payload STRING NULL
)
DUPLICATE KEY(ts, uid)
DISTRIBUTED BY HASH(uid) BUCKETS 4
PROPERTIES ('replication_num' = '1');"

echo ""
echo "========== 步骤 4.2：灌入同样的 100 万行数据 =========="
echo "--- 先灌结构化表（作为数据源）---"
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

echo "--- 从结构化表生成 VARIANT 表（拼成 JSON 写入）---"
runq "INSERT INTO log_variant
SELECT ts, uid,
  CONCAT('{\"city\":\"', city, '\",\"device\":\"', device, '\",\"cost\":', CAST(cost AS STRING), '}') AS payload
FROM log_typed;"
runq "SELECT COUNT(*) AS variant_rows FROM log_variant;"

echo "--- 同样内容存成 JSON 字符串 ---"
runq "INSERT INTO log_json
SELECT ts, uid,
  CONCAT('{\"city\":\"', city, '\",\"device\":\"', device, '\",\"cost\":', CAST(cost AS STRING), '}') AS payload
FROM log_typed;"
runq "SELECT COUNT(*) AS json_rows FROM log_json;"

echo ""
echo "--- 抽样确认三张表内容一致 ---"
runq "SELECT uid, payload FROM log_variant ORDER BY uid LIMIT 2;"
runq "SELECT uid, city, device, cost FROM log_typed ORDER BY uid LIMIT 2;"

echo ""
echo "========== 步骤 4.3：看 VARIANT 把 JSON 拆成了哪些列 =========="
runq "SET describe_extend_variant_column = true; DESC log_variant;"
echo ""
echo "👆 看到 payload.city / payload.cost / payload.device 三行了吗？"
echo "   JSON 的每个字段都变成了【真正的列存子列】，"
echo "   和其他普通列一样享受列存压缩和向量化。这就是它快的根本原因。"

echo ""
echo "========== 步骤 4.3b：动态 schema —— 字段变了不用改表 =========="
echo ""
echo "--- 建一张临时表，插三条字段完全不同的日志 ---"
runq "DROP TABLE IF EXISTS v_probe;"
runq "CREATE TABLE v_probe (
  id BIGINT NOT NULL,
  log VARIANT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 2
PROPERTIES ('replication_num' = '1');"

runq "INSERT INTO v_probe VALUES
  (1, '{\"type\":\"login\",\"user\":\"alice\",\"ip\":\"1.2.3.4\"}'),
  (2, '{\"type\":\"pay\",\"user\":\"bob\",\"amount\":99.9,\"currency\":\"CNY\"}'),
  (3, '{\"type\":\"click\",\"user\":\"carol\",\"elem\":\"btn_buy\",\"page\":3}');"

runq "SELECT id, log['type'] AS type, log['user'] AS user FROM v_probe ORDER BY id;"
echo ""
echo "--- 再看子列：新字段自己出现了，没执行过任何 ALTER TABLE ---"
runq "SET describe_extend_variant_column = true; DESC v_probe;"
echo ""
echo "👆 预期看到 log.amount / log.currency / log.elem / log.ip / log.page / log.type / log.user"
echo "   三条记录字段完全不同，VARIANT 全部接住了。这就是「动态 schema」。"

echo ""
echo "--- ⚠️ 嵌套数组不能直接下标访问 ---"
runq "SELECT log['tags']                                              AS a FROM v_probe WHERE id = 3;"
runq "SELECT log['tags'][0]                                           AS b FROM v_probe WHERE id = 3;"
runq "SELECT element_at(CAST(log['tags'] AS ARRAY<STRING>), 1)        AS c FROM v_probe WHERE id = 3;"
echo "👆 b 会返回 NULL（不是报错，是静默的 NULL）。正确写法是 c。"
echo "   注意：v_probe 里没有 tags 字段，这三行是为了演示写法差异。"
echo "   想在真实数据上试，往表里插一条带数组的："
echo "     INSERT INTO v_probe VALUES (4, '{\"tags\":[\"a\",\"b\"]}');"

echo ""
echo "========== 步骤 4.4：⚠️ 必踩的坑 —— 子列不能直接 GROUP BY =========="
echo ""
echo "--- 4.4a 这样写会报错 ---"
runq "SELECT payload['city'] AS city, COUNT(*) AS cnt
FROM log_variant GROUP BY payload['city'] ORDER BY city;"
echo ""
echo "   报错：variant column must use with specific function,"
echo "         and don't support filter, group by or order by"

echo ""
echo "--- 4.4b 正确写法：先 CAST ---"
runq "SELECT CAST(payload['city'] AS VARCHAR(32)) AS city, COUNT(*) AS cnt
FROM log_variant
GROUP BY CAST(payload['city'] AS VARCHAR(32))
ORDER BY city;"
echo ""
echo "👆 规则：WHERE 里可以直接用，GROUP BY / ORDER BY 前必须 CAST"

echo ""
echo "========== 步骤 4.5：过滤场景耗时对比（各跑 4 次）=========="
echo "--- 结构化列 ---"
for i in 1 2 3 4; do runq "SELECT COUNT(*) AS cnt FROM log_typed WHERE device = 'iOS';" > /dev/null; done
echo "--- VARIANT 子列 ---"
for i in 1 2 3 4; do runq "SELECT COUNT(*) AS cnt FROM log_variant WHERE payload['device'] = 'iOS';" > /dev/null; done
echo "--- JSON 字符串 ---"
for i in 1 2 3 4; do runq "SELECT COUNT(*) AS cnt FROM log_json WHERE get_json_string(payload, '\$.device') = 'iOS';" > /dev/null; done

echo ""
echo "==================== 步骤 4 完成 ===================="
echo "下一步：bash lesson08-step5.sh  （查看实测耗时与磁盘占用）"

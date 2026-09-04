#!/bin/bash
# ============================================================
# 课 8 第四幕 步骤 1：搭建 Join 实验环境
#
# ⚠️ 最重要的一个坑（课 7 踩过，本课再次强调）：
#    docker exec 必须带 -i！
#    docker exec 默认不转发 stdin，不加 -i 时
#    `echo "$SQL" | docker exec ... mysql` 会静默无输出，
#    建表/造数全部失败却不报错，后续步骤全对不上。
#    这是前几课"掩盖真相"陷阱的又一次变体。
#
# 用法：bash lesson08-setup.sh
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 步骤 1.1：确认环境 =========="
echo "--- 容器状态（应看到 doris-learn Up ... healthy）---"
docker ps --format '{{.Names}} | {{.Status}}' | grep doris

echo ""
echo "--- Doris 版本与 BE 数量 ---"
runq "SHOW FRONTENDS\G" | grep -E "Version" | head -2
echo "SHOW BACKENDS\G" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password" | grep -E "Host|Alive"

echo ""
echo "========== 步骤 1.2：确认 orders 表还在（课 3 建的）=========="
runq "SHOW TABLES;" | grep -E "^orders$|^orders_dup$"

echo ""
echo "--- orders 的结构（注意分桶键是 province，8 个桶）---"
runq "SHOW CREATE TABLE orders\G" | grep -E "DUPLICATE KEY|DISTRIBUTED BY"

echo ""
echo "--- orders 的行数（约 2150 万，这步要几秒）---"
runq "SELECT COUNT(*) AS orders_rows FROM orders;"

echo ""
echo "========== 步骤 1.3：关掉 SQL 缓存（做性能对比的前提）=========="
echo "--- 关闭前 ---"
runq "SHOW VARIABLES LIKE 'enable_sql_cache';"
runq "SET GLOBAL enable_sql_cache = false;"
echo "    （全局设置需要几秒生效，等 3 秒）"
sleep 3
echo "--- 关闭后 ---"
runq "SHOW VARIABLES LIKE 'enable_sql_cache';"

echo ""
echo "⚠️ 为什么要关？"
echo "   SQL Cache 默认开启。同一条 SQL 第二次跑会直接返回缓存结果（耗时 1ms），"
echo "   导致你测出的'优化效果'全是假的。课 7 就栽在这上面。"
echo "   课 8 全部实验结束后，记得恢复：SET GLOBAL enable_sql_cache = true;"

echo ""
echo "========== 步骤 1.4：打开 Profile（看时间花在哪）=========="
runq "SET GLOBAL enable_profile = true;"
sleep 2
runq "SHOW VARIABLES LIKE 'enable_profile';"

echo ""
echo "========== 步骤 1.5：建维度表（小表，8 行）=========="
runq "DROP TABLE IF EXISTS dim_region;"
runq "CREATE TABLE dim_region (
  province VARCHAR(16) NOT NULL,
  region VARCHAR(16) NOT NULL,
  level VARCHAR(8) NOT NULL DEFAULT 'A'
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 2
PROPERTIES ('replication_num' = '1');"

echo "--- 从 orders 里取出真实的省份，人工标注大区 ---"
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

echo "--- 确认 8 行都进去了 ---"
runq "SELECT COUNT(*) AS dim_rows FROM dim_region;"
runq "SELECT * FROM dim_region ORDER BY province;"

echo ""
echo "========== 步骤 1.6：建对照维表（10 万行）=========="
echo "--- 先从 orders 取 100 万行做一个可控规模的事实表 ---"
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
PROPERTIES ('replication_num' = '1', 'colocate_with' = 'prov_group');"
echo "    ↑ 注意 colocate_with='prov_group'：把左表也加进共存组，"
echo "      否则步骤 2 里 Colocate Join 出不来（两侧必须同组）"
runq "INSERT INTO fact_1m SELECT order_date, province, city, user_id, amount FROM orders LIMIT 1000000;"
runq "SELECT COUNT(*) AS fact_1m_rows FROM fact_1m;"

echo ""
echo "--- 建两张结构完全相同、只在 colocate 属性上不同的维表 ---"
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

echo ""
echo "--- 再建一张 colocate 大表 fact_prov（步骤 2 演示 Colocate Join 要用）---"
echo "    为什么还要一张？因为 Colocate 要求【两张表都在同一个组里】，"
echo "    而 colo_dim 只有 10 万行，优化器在它上面倾向选 Broadcast。"
echo "    fact_prov 有 200 万行，两侧都够大，COLOCATE 才会稳定出现。"
runq "DROP TABLE IF EXISTS fact_prov;"
runq "CREATE TABLE fact_prov (
  province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ('replication_num' = '1', 'colocate_with' = 'prov_group');"
runq "INSERT INTO fact_prov SELECT province, user_id, amount FROM orders LIMIT 2000000;"
runq "SELECT COUNT(*) AS fact_prov_rows FROM fact_prov;"
runq "ANALYZE TABLE fact_prov WITH SYNC;"

echo ""
echo "========== 步骤 1.7：刷新统计信息 =========="
echo "--- 让优化器知道每张表有多少行，否则它可能选错 Join 策略 ---"
runq "ANALYZE TABLE fact_1m WITH SYNC;"
runq "ANALYZE TABLE colo_dim WITH SYNC;"
runq "ANALYZE TABLE non_colo_dim WITH SYNC;"
runq "ANALYZE TABLE dim_region WITH SYNC;"

echo ""
echo "========== 步骤 1.8：确认 colocation group 状态 =========="
echo "--- IsStable 必须是 true，否则 Colocate Join 不生效 ---"
runq "SHOW PROC '/colocation_group';"

echo ""
echo "==================== 步骤 1 完成 ===================="
echo "下一步：bash lesson08-step2.sh  （看四种 Join 策略的 EXPLAIN 标记）"

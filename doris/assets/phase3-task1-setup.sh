#!/usr/bin/env bash
# Phase 3 · Task 1：建库 + 四层建表 + 维表
# 用法：bash assets/phase3-task1-setup.sh
# 所有报错原文保留，不 grep 掉
set -u
Q() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot "$@" 2>&1; }

echo "=========================================="
echo " Phase 3 · Task 1：需求与建模"
echo "=========================================="
echo

echo "--- 0. 前置检查：集群状态 ---"
Q -e "SHOW BACKENDS\G" | grep -E "Alive:|HeartbeatPort:"
echo

echo "--- 1. 建库 dw ---"
Q -e "CREATE DATABASE IF NOT EXISTS dw;"
echo

echo "--- 2. 清理同名旧表（若存在，保证幂等）---"
Q dw -e "DROP TABLE IF EXISTS ads_prov_month_top;"
Q dw -e "DROP TABLE IF EXISTS dws_prov_month;"
Q dw -e "DROP TABLE IF EXISTS dwd_orders;"
Q dw -e "DROP TABLE IF EXISTS ods_orders;"
Q dw -e "DROP TABLE IF EXISTS dim_province;"
echo "旧表清理完成"
echo

echo "--- 3. 建 ODS 层：ods_orders（Duplicate，贴源保脏数据）---"
Q dw -e "
CREATE TABLE ods_orders (
    order_date   DATE           NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    city         VARCHAR(32)    NOT NULL,
    user_id      BIGINT         NOT NULL,
    product_id   INT            NOT NULL,
    category     VARCHAR(32)    NOT NULL,
    quantity     INT            NOT NULL,
    amount       DECIMAL(10,2)  NOT NULL,
    pay_type     VARCHAR(16)    NOT NULL,
    status       TINYINT        NOT NULL,
    created_at   DATETIME       NOT NULL,
    updated_at   DATETIME       NOT NULL
)
DUPLICATE KEY(order_date, province, city)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES (
    'replication_num' = '1',
    'dynamic_partition.enable' = 'true',
    'dynamic_partition.time_unit' = 'MONTH',
    'dynamic_partition.start' = '-24',
    'dynamic_partition.end' = '3',
    'dynamic_partition.prefix' = 'p',
    'dynamic_partition.create_history_partition' = 'true'
);"
echo

echo "--- 4. 建 DWD 层：dwd_orders（Unique MoW，去重）---"
Q dw -e "
CREATE TABLE dwd_orders (
    order_date   DATE           NOT NULL,
    user_id      BIGINT         NOT NULL,
    order_id     BIGINT         NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    city         VARCHAR(32)    NOT NULL,
    product_id   INT            NOT NULL,
    category     VARCHAR(32)    NOT NULL,
    quantity     INT            NOT NULL,
    amount       DECIMAL(10,2)  NOT NULL,
    pay_type     VARCHAR(16)    NOT NULL,
    status       TINYINT        NOT NULL,
    created_at   DATETIME       NOT NULL
)
UNIQUE KEY(order_date, user_id, order_id)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES (
    'replication_num' = '1',
    'enable_unique_key_merge_on_write' = 'true',
    'dynamic_partition.enable' = 'true',
    'dynamic_partition.time_unit' = 'MONTH',
    'dynamic_partition.start' = '-24',
    'dynamic_partition.end' = '3',
    'dynamic_partition.prefix' = 'p',
    'dynamic_partition.create_history_partition' = 'true'
);"
echo

echo "--- 5. 建 DWS 层：dws_prov_month（Aggregate，预聚合）---"
Q dw -e "
CREATE TABLE dws_prov_month (
    stat_month   DATE           NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    order_cnt    BIGINT         SUM   DEFAULT '0',
    uv           BITMAP         BITMAP_UNION,
    total_amount DECIMAL(18,2)  SUM   DEFAULT '0',
    max_amount   DECIMAL(10,2)  MAX   DEFAULT '0'
)
AGGREGATE KEY(stat_month, province)
PARTITION BY RANGE(stat_month) ()
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES (
    'replication_num' = '1',
    'dynamic_partition.enable' = 'true',
    'dynamic_partition.time_unit' = 'MONTH',
    'dynamic_partition.start' = '-24',
    'dynamic_partition.end' = '3',
    'dynamic_partition.prefix' = 'p',
    'dynamic_partition.create_history_partition' = 'true'
);"
echo

echo "--- 6. 建 ADS 层：ads_prov_month_top（Duplicate，最终结果）---"
# 注意：Key 列必须是 schema 的有序前缀。
# 写成 DUPLICATE KEY(stat_month, rank_no) 而列顺序是 (stat_month, province, rank_no, ...)
# 会报：Key columns should be a ordered prefix of the schema
Q dw -e "
CREATE TABLE ads_prov_month_top (
    stat_month   DATE           NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    rank_no      INT            NOT NULL,
    total_amount DECIMAL(18,2)  NOT NULL,
    order_cnt    BIGINT         NOT NULL,
    uv           BIGINT         NOT NULL
)
DUPLICATE KEY(stat_month, province, rank_no)
PARTITION BY RANGE(stat_month) ()
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES (
    'replication_num' = '1',
    'dynamic_partition.enable' = 'true',
    'dynamic_partition.time_unit' = 'MONTH',
    'dynamic_partition.start' = '-24',
    'dynamic_partition.end' = '3',
    'dynamic_partition.prefix' = 'p',
    'dynamic_partition.create_history_partition' = 'true'
);"
echo

echo "--- 7. 建维表：dim_province（province 分 4 桶，与 DWS Colocate）---"
Q dw -e "
CREATE TABLE dim_province (
    province     VARCHAR(16)    NOT NULL,
    region       VARCHAR(16)    NOT NULL,
    region_code  INT            NOT NULL
)
DUPLICATE KEY(province)
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES (
    'replication_num' = '1'
);"
echo

echo "--- 8. 灌维表数据（⚠️ 必须从数据里来，不能手写 VALUES）---"
echo "    【事故记录】第一版手写 ('广东','华南'),('广西','华南'),('上海','华东')..."
echo "    结果：真实数据里的 四川/河南/湖北/福建 维表里没有，"
echo "          而手写的 广西/海南/上海/北京 数据里根本没有。"
echo "    Task 3 的 MV 用 INNER JOIN 关联时静默丢掉一半数据（48 行 vs 应有 96 行，"
echo "    金额 125 亿 vs 应有 250 亿）。不报错、不警告，只有对账才能发现。"
echo "    正确做法：从源表 DISTINCT 出来。"
Q dw -e "
INSERT INTO dim_province
SELECT province,
  CASE WHEN province IN ('广东','广西','海南','福建') THEN '华南'
       WHEN province IN ('江苏','浙江','山东','河南','湖北','四川') THEN '华东华中'
       ELSE '其他' END AS region,
  CASE WHEN province IN ('广东','广西','海南','福建') THEN 1
       WHEN province IN ('江苏','浙江','山东') THEN 2
       WHEN province IN ('河南','湖北','四川') THEN 3
       ELSE 9 END AS region_code
FROM (SELECT DISTINCT province FROM shop.orders) t;"
echo

echo "--- 8.1 覆盖性校验：源表有、维表没有的省份必须为 0 ---"
Q -e "
SELECT COUNT(*) AS missing_in_dim FROM (
  SELECT DISTINCT o.province
  FROM shop.orders o
  LEFT JOIN dw.dim_province d ON o.province = d.province
  WHERE d.province IS NULL
) t;"
echo "    （应为 0）"
echo

echo "--- 9. 校验：表清单 ---"
Q dw -e "SHOW TABLES;"
echo

echo "--- 10. 校验：各表分区数（动态分区应自动生成 28 个）---"
# 用 information_schema 计数，别用 SHOW PARTITIONS | grep -c "^p"
# 后者的表头行与管道缓冲会让计数在某些 shell 下失真
for t in ods_orders dwd_orders dws_prov_month ads_prov_month_top; do
  N=$(Q -e "SELECT COUNT(*) FROM information_schema.partitions WHERE TABLE_SCHEMA='dw' AND TABLE_NAME='$t';" | tail -1)
  echo "$t 分区数: $N"
done
echo

echo "--- 11. 校验：ods_orders 分区首尾（覆盖 24 个月历史 + 3 个月未来）---"
Q -e "SELECT MIN(PARTITION_NAME) AS first_p, MAX(PARTITION_NAME) AS last_p, COUNT(*) AS cnt FROM information_schema.partitions WHERE TABLE_SCHEMA='dw' AND TABLE_NAME='ods_orders';"
echo

echo "--- 12. 校验：维表数据 ---"
Q dw -e "SELECT * FROM dim_province ORDER BY region_code, province;"
echo

echo "--- 13. 校验：集群 tablet 健康 ---"
Q -e "SHOW PROC '/cluster_health/tablet_health';" | grep -E "dw|Total"
echo

echo "=========================================="
echo "Task 1 建模完成"
echo "=========================================="

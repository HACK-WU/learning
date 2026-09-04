#!/bin/bash
# 课 4：建实验表 —— 分区 vs 不分区，不同分桶键的倾斜对比
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 表 A：不分区 + 按 province 分桶（课 2 的坑，8 个值）==========="
$D -e "
DROP TABLE IF EXISTS t_nopart_prov;
CREATE TABLE t_nopart_prov (
    order_date DATE NOT NULL, province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 表 B：不分区 + 按 user_id 分桶（183 万基数）==========="
$D -e "
DROP TABLE IF EXISTS t_nopart_user;
CREATE TABLE t_nopart_user (
    order_date DATE NOT NULL, province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 表 C：按月分区 + 按 user_id 分桶 ==========="
$D -e "
DROP TABLE IF EXISTS t_part_month;
CREATE TABLE t_part_month (
    order_date DATE NOT NULL, province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(order_date, province, city)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1', 'dynamic_partition.enable'='true',
  'dynamic_partition.time_unit'='MONTH', 'dynamic_partition.start'='-24',
  'dynamic_partition.end'='24', 'dynamic_partition.prefix'='p',
  'dynamic_partition.buckets'='8');" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "--- 查看动态分区是否自动创建了分区 ---"
$D -e "SHOW PARTITIONS FROM t_part_month;" 2>/dev/null | grep -vE "^Warning|Using a password" | head -8

echo ""
echo "=========== 导入数据（三张表相同数据）==========="
for t in t_nopart_prov t_nopart_user t_part_month; do
  S=$(date +%s)
  $D -e "INSERT INTO $t SELECT order_date, province, city, user_id, amount, quantity FROM orders;" 2>/dev/null >/dev/null
  E=$(date +%s)
  echo "  $t: $((E-S)) 秒"
done

echo ""
echo "=========== 验证行数 ==========="
$D -e "
SELECT 't_nopart_prov' AS tbl, COUNT(*) AS rows FROM t_nopart_prov
UNION ALL SELECT 't_nopart_user', COUNT(*) FROM t_nopart_user
UNION ALL SELECT 't_part_month', COUNT(*) FROM t_part_month;
" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "SETUP4_DONE"

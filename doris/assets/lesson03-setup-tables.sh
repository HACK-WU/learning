#!/bin/bash
# 课 3：建三种模型的表 + 导入数据
# 与课 2 的区别：分桶键改用 city（50 个），吸取课 2 按 province（8 个）倾斜的教训
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

run() {
  echo "--- $1 ---"
  docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "$2" 2>&1 | grep -vE "^Warning|Using a password"
}

echo "=========== 1. Duplicate 明细表（控制组）==========="
run "建表" "
DROP TABLE IF EXISTS orders_dup;
CREATE TABLE orders_dup (
    order_date DATE NOT NULL,
    province   VARCHAR(16) NOT NULL,
    city       VARCHAR(32) NOT NULL,
    user_id    BIGINT NOT NULL,
    product_id INT NOT NULL,
    category   VARCHAR(32) NOT NULL,
    quantity   INT NOT NULL,
    amount     DECIMAL(10,2) NOT NULL,
    pay_type   VARCHAR(16) NOT NULL,
    status     TINYINT NOT NULL,
    remark     VARCHAR(255) NOT NULL DEFAULT 'xxx',
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
)
DUPLICATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(city) BUCKETS 8
PROPERTIES ('replication_num' = '1');
"

echo ""
echo "--- 导入（INSERT INTO ... SELECT，Doris 内部导入）---"
START=$(date +%s)
run "导入" "INSERT INTO orders_dup SELECT * FROM orders;"
END=$(date +%s)
echo "耗时: $((END-START)) 秒"
run "行数" "SELECT COUNT(*) AS total FROM orders_dup;"

echo ""
echo "=========== 2. Aggregate 聚合表 ==========="
run "建表" "
DROP TABLE IF EXISTS orders_agg;
CREATE TABLE orders_agg (
    order_date   DATE NOT NULL,
    province     VARCHAR(16) NOT NULL,
    city         VARCHAR(32) NOT NULL,
    order_cnt    BIGINT        SUM        DEFAULT '0',
    quantity_sum BIGINT        SUM        DEFAULT '0',
    amount_sum   DECIMAL(18,2) SUM        DEFAULT '0',
    amount_max   DECIMAL(10,2) MAX        DEFAULT '0',
    last_status  TINYINT       REPLACE    DEFAULT '0'
)
AGGREGATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(city) BUCKETS 8
PROPERTIES ('replication_num' = '1');
"

echo ""
echo "--- 导入（边查边聚合）---"
START=$(date +%s)
run "导入" "
INSERT INTO orders_agg
SELECT order_date, province, city,
       COUNT(*)       AS order_cnt,
       SUM(quantity)  AS quantity_sum,
       SUM(amount)    AS amount_sum,
       MAX(amount)    AS amount_max,
       MAX(status)    AS last_status
FROM orders
GROUP BY order_date, province, city;
"
END=$(date +%s)
echo "耗时: $((END-START)) 秒"
run "行数" "SELECT COUNT(*) AS total FROM orders_agg;"

echo ""
echo "=========== 3. Unique 主键表（MOW，显式开启）==========="
run "建表" "
DROP TABLE IF EXISTS orders_uniq_mow;
CREATE TABLE orders_uniq_mow (
    order_date DATE NOT NULL,
    province   VARCHAR(16) NOT NULL,
    city       VARCHAR(32) NOT NULL,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    status     TINYINT,
    updated_at DATETIME
)
UNIQUE KEY(order_date, province, city)
DISTRIBUTED BY HASH(city) BUCKETS 8
PROPERTIES ('replication_num' = '1', 'enable_unique_key_merge_on_write' = 'true');
"

echo ""
echo "=========== 4. Unique 主键表（MOR，显式关闭）==========="
run "建表" "
DROP TABLE IF EXISTS orders_uniq_mor;
CREATE TABLE orders_uniq_mor (
    order_date DATE NOT NULL,
    province   VARCHAR(16) NOT NULL,
    city       VARCHAR(32) NOT NULL,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    status     TINYINT,
    updated_at DATETIME
)
UNIQUE KEY(order_date, province, city)
DISTRIBUTED BY HASH(city) BUCKETS 8
PROPERTIES ('replication_num' = '1', 'enable_unique_key_merge_on_write' = 'false');
"

echo ""
echo "=========== 5. 查默认行为：不指定 MOW 时是什么？==========="
run "建默认表" "
DROP TABLE IF EXISTS orders_uniq_default;
CREATE TABLE orders_uniq_default (
    order_date DATE NOT NULL,
    province   VARCHAR(16) NOT NULL,
    city       VARCHAR(32) NOT NULL,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    status     TINYINT,
    updated_at DATETIME
)
UNIQUE KEY(order_date, province, city)
DISTRIBUTED BY HASH(city) BUCKETS 8
PROPERTIES ('replication_num' = '1');
"
run "默认表的属性" "SHOW CREATE TABLE orders_uniq_default\G"

echo ""
echo "SETUP_DONE"

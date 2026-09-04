#!/bin/bash
# 课 2：建库建表（在容器内执行，避免 docker cp 路径问题）
SQL=$(cat <<'EOSQL'
CREATE DATABASE IF NOT EXISTS shop;
USE shop;
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_date  DATE           NOT NULL,
    province    VARCHAR(16)    NOT NULL,
    city        VARCHAR(32)    NOT NULL,
    user_id     BIGINT         NOT NULL,
    product_id  INT            NOT NULL,
    category    VARCHAR(32)    NOT NULL,
    quantity    INT            NOT NULL,
    amount      DECIMAL(10,2)  NOT NULL,
    pay_type    VARCHAR(16)    NOT NULL,
    status      TINYINT        NOT NULL,
    remark      VARCHAR(255)   NOT NULL DEFAULT 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    created_at  DATETIME       NOT NULL,
    updated_at  DATETIME       NOT NULL
)
DUPLICATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(province) BUCKETS 8
PROPERTIES ("replication_num" = "1");
EOSQL
)

docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "$SQL" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== DESC orders ==="
docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "USE shop; DESC orders;" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== SHOW CREATE TABLE（看 Doris 补了什么）==="
docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "USE shop; SHOW CREATE TABLE orders\G" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "CREATE_DONE"

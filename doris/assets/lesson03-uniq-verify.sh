#!/bin/bash
# 课 3：Unique 模型验证 —— upsert 语义 + MOW vs MOR 差异
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
DA="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=========== 1. Unique 的 upsert 语义：同一主键重复插入会覆盖 ==========="
echo "--- 第一次插入 ---"
$D -e "INSERT INTO orders_uniq_mow VALUES ('2025-01-01','广东','深圳', 1001, 99.50, 1, '2025-01-01 10:00:00');" 2>/dev/null >/dev/null
$D -e "SELECT * FROM orders_uniq_mow WHERE city='深圳';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "--- 第二次插入同一主键，但金额和状态不同 ---"
$D -e "INSERT INTO orders_uniq_mow VALUES ('2025-01-01','广东','深圳', 1002, 888.88, 2, '2025-01-01 11:00:00');" 2>/dev/null >/dev/null
echo "结果（应该是后者覆盖前者）："
$D -e "SELECT * FROM orders_uniq_mow WHERE city='深圳';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 2. 对照：Duplicate 表会保留两条 ==========="
$D -e "INSERT INTO orders_dup (order_date,province,city,user_id,product_id,category,quantity,amount,pay_type,status,remark,created_at,updated_at) VALUES ('2025-01-01','广东','深圳',1001,1,'cat',1,99.50,'wx',1,'r','2025-01-01 10:00:00','2025-01-01 10:00:00');" 2>/dev/null >/dev/null
$D -e "INSERT INTO orders_dup (order_date,province,city,user_id,product_id,category,quantity,amount,pay_type,status,remark,created_at,updated_at) VALUES ('2025-01-01','广东','深圳',1002,1,'cat',1,888.88,'wx',2,'r','2025-01-01 11:00:00','2025-01-01 11:00:00');" 2>/dev/null >/dev/null
echo "结果（应该保留两条）："
$D -e "SELECT order_date,province,city,user_id,amount,status FROM orders_dup WHERE city='深圳' AND user_id IN (1001,1002);" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 3. MOW vs MOR：写入后立即可见吗？==========="
echo "--- MOW 表：连续 3 次更新同一主键 ---"
for v in 10 20 30; do
  $D -e "INSERT INTO orders_uniq_mow VALUES ('2025-01-02','广东','广州', 2001, $v.00, 1, '2025-01-02 10:00:00');" 2>/dev/null >/dev/null
done
echo "MOW 结果："
$D -e "SELECT city, amount FROM orders_uniq_mow WHERE city='广州';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "--- MOR 表：同样操作 ---"
for v in 10 20 30; do
  $D -e "INSERT INTO orders_uniq_mor VALUES ('2025-01-02','广东','广州', 2001, $v.00, 1, '2025-01-02 10:00:00');" 2>/dev/null >/dev/null
done
echo "MOR 结果："
$D -e "SELECT city, amount FROM orders_uniq_mor WHERE city='广州';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 4. MOW/MOR 的可见版本数差异（核心区别）==========="
echo "--- MOW 表 tablet 的 version count（应该少）---"
$D --batch -e "SHOW TABLETS FROM orders_uniq_mow;" 2>/dev/null | awk -F'\t' 'NR>1{print "  VersionCount="$16}' | head -3
echo "--- MOR 表 tablet 的 version count（应该多）---"
$D --batch -e "SHOW TABLETS FROM orders_uniq_mor;" 2>/dev/null | awk -F'\t' 'NR>1{print "  VersionCount="$16}' | head -3

echo ""
echo "=========== 5. Unique 与 Aggregate REPLACE 的关系 ==========="
echo "--- 建一张 Aggregate REPLACE 表（所有列都 REPLACE）---"
$D -e "
DROP TABLE IF EXISTS orders_agg_replace;
CREATE TABLE orders_agg_replace (
    order_date DATE NOT NULL,
    province   VARCHAR(16) NOT NULL,
    city       VARCHAR(32) NOT NULL,
    user_id    BIGINT      REPLACE,
    amount     DECIMAL(10,2) REPLACE,
    status     TINYINT     REPLACE,
    updated_at DATETIME    REPLACE
)
AGGREGATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(city) BUCKETS 8
PROPERTIES ('replication_num' = '1');" 2>/dev/null >/dev/null

echo "--- 插入同一主键两次，看 REPLACE 行为 ---"
$D -e "INSERT INTO orders_agg_replace VALUES ('2025-01-03','广东','东莞', 3001, 111.00, 1, '2025-01-03 10:00:00');" 2>/dev/null >/dev/null
$D -e "INSERT INTO orders_agg_replace VALUES ('2025-01-03','广东','东莞', 3002, 222.00, 2, '2025-01-03 11:00:00');" 2>/dev/null >/dev/null
echo "Aggregate REPLACE 结果："
$D -e "SELECT * FROM orders_agg_replace WHERE city='东莞';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 6. Aggregate 表的非聚合列限制 ==========="
echo "--- 尝试在 Aggregate 表里用 SUM 列做 WHERE 过滤（应能跑但语义特殊）---"
$D -e "SELECT COUNT(*) FROM orders_agg WHERE order_cnt > 100;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 7. 存储对比（最终）==========="
$D -e "SHOW DATA;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "UNIQ_DONE"

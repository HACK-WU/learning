#!/bin/bash
# 课 5：验证 Key 列顺序的硬约束 —— Key 列必须是建表语句的前几列
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 1. 先看 CREATE TABLE 到底报什么错 ==========="
echo "--- 列顺序(order_date,province,city)，KEY 声明(province,city,order_date) ---"
$D -e "
CREATE TABLE k_wrong (
    order_date DATE NOT NULL, province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(province, city, order_date)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>&1 | grep -vE "^Warning|Using a password" | head -3

echo ""
echo "=========== 2. 正确的写法：列顺序与 KEY 顺序一致 ==========="
$D -e "
DROP TABLE IF EXISTS k_prov_first;
CREATE TABLE k_prov_first (
    province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL, order_date DATE NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(province, city, order_date)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>&1 | grep -vE "^Warning|Using a password" | head -3
echo "  建表结果: $?"

echo ""
echo "=========== 3. 确认表存在 ==========="
$D -e "SHOW TABLES LIKE 'k_prov%';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 4. 导入数据 ==========="
S=$(date +%s)
$D -e "INSERT INTO k_prov_first SELECT province, city, order_date, user_id, amount, quantity FROM orders;" 2>&1 | grep -vE "^Warning|Using a password" | head -3
E=$(date +%s)
echo "  耗时: $((E-S)) 秒"
echo -n "  行数: "
$D --batch -e "SELECT COUNT(*) FROM k_prov_first;" 2>/dev/null | tail -1

echo ""
echo "=========== 5. 现在对比两表的 EXPLAIN ==========="
echo "--- k_date_first (KEY: order_date,province,city) 查 province ---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_date_first WHERE province='广东';" 2>/dev/null | grep -iE "PREDICATES|cardinality=|tablets=" | head -4

echo ""
echo "--- k_prov_first (KEY: province,city,order_date) 查 province ---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_prov_first WHERE province='广东';" 2>/dev/null | grep -iE "PREDICATES|cardinality=|tablets=" | head -4

echo ""
echo "=========== 6. 查 order_date 的对比（反过来）==========="
echo "--- k_date_first 查 order_date（第1列）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_date_first WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "PREDICATES|cardinality=" | head -4

echo ""
echo "--- k_prov_first 查 order_date（第3列）---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_prov_first WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "PREDICATES|cardinality=" | head -4

echo ""
echo "=========== 7. 实际耗时对比（多跑几次取稳定值）==========="
echo "--- 查 province='广东' ---"
for i in 1 2 3; do
  S=$(date +%s.%N); $D -e "SELECT COUNT(*), ROUND(SUM(amount)) FROM k_date_first WHERE province='广东';" 2>/dev/null >/dev/null; E=$(date +%s.%N)
  printf '  k_date_first 第%d次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done
for i in 1 2 3; do
  S=$(date +%s.%N); $D -e "SELECT COUNT(*), ROUND(SUM(amount)) FROM k_prov_first WHERE province='广东';" 2>/dev/null >/dev/null; E=$(date +%s.%N)
  printf '  k_prov_first 第%d次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done

echo ""
echo "=========== 8. 结果正确性 ==========="
echo -n "  k_date_first: "
$D --batch -e "SELECT COUNT(*), ROUND(SUM(amount)) FROM k_date_first WHERE province='广东';" 2>/dev/null | tail -1
echo -n "  k_prov_first: "
$D --batch -e "SELECT COUNT(*), ROUND(SUM(amount)) FROM k_prov_first WHERE province='广东';" 2>/dev/null | tail -1

echo ""
echo "FIX5_DONE"

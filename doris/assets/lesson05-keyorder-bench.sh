#!/bin/bash
# 课 5 实验 1：Key 列顺序对查询的影响（前缀索引实证）
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 建两张 Key 列顺序不同的表 ==========="
# 表 1：Key = (order_date, province, city) —— 时间在前
$D -e "
DROP TABLE IF EXISTS k_date_first;
CREATE TABLE k_date_first (
    order_date DATE NOT NULL, province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>/dev/null | grep -vE "^Warning|Using a password"

# 表 2：Key = (province, city, order_date) —— 地区在前
$D -e "
DROP TABLE IF EXISTS k_prov_first;
CREATE TABLE k_prov_first (
    order_date DATE NOT NULL, province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(province, city, order_date)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>/dev/null | grep -vE "^Warning|Using a password"

echo "  两张表建好了（列完全相同，只有 Key 顺序不同）"

echo ""
echo "=========== 导入相同数据 ==========="
for t in k_date_first k_prov_first; do
  S=$(date +%s)
  $D -e "INSERT INTO $t SELECT order_date, province, city, user_id, amount, quantity FROM orders;" 2>/dev/null >/dev/null
  E=$(date +%s)
  echo "  $t: $((E-S)) 秒"
done

echo ""
echo "=========== 验证行数 ==========="
$D -e "
SELECT 'k_date_first' AS tbl, COUNT(*) AS rows FROM k_date_first
UNION ALL SELECT 'k_prov_first', COUNT(*) FROM k_prov_first;
" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 实验 A：查 province（Key 的第 2 列 vs 第 1 列）==========="
echo "--- k_date_first：province 是第 2 列，前面有 order_date → 前缀索引用不上 ---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_date_first WHERE province='广东';" 2>/dev/null | grep -iE "predicates|cardinality|tablets=|PREDICATES" | head -6

echo ""
echo "--- k_prov_first：province 是第 1 列 → 前缀索引直接命中 ---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_prov_first WHERE province='广东';" 2>/dev/null | grep -iE "predicates|cardinality|tablets=" | head -6

echo ""
echo "=========== 实验 B：查 order_date（Key 的第 1 列 vs 第 3 列）==========="
echo "--- k_date_first：order_date 是第 1 列 → 命中 ---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_date_first WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "predicates|cardinality|PREDICATES" | head -6

echo ""
echo "--- k_prov_first：order_date 是第 3 列 → 用不上前缀索引 ---"
$D -e "EXPLAIN SELECT COUNT(*), ROUND(SUM(amount)) FROM k_prov_first WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';" 2>/dev/null | grep -iE "predicates|cardinality|PREDICATES" | head -6

echo ""
echo "=========== 实验 C：命中前缀 vs 不命中，实际耗时 ==========="
echo "--- 查 province='广东' ---"
for t in k_date_first k_prov_first; do
  S=$(date +%s.%N)
  $D -e "SELECT COUNT(*), ROUND(SUM(amount)) FROM $t WHERE province='广东';" 2>/dev/null >/dev/null
  E=$(date +%s.%N)
  printf '  %s: %.3f 秒\n' "$t" "$(echo "$E - $S" | bc)"
done

echo ""
echo "=========== 实验 D：ZoneMap（自动 min/max 索引）验证 ==========="
echo "--- order_date 是第 1 列（k_date_first），范围查询能靠 ZoneMap 跳过 block ---"
$D -e "EXPLAIN SELECT COUNT(*) FROM k_date_first WHERE order_date = '2025-06-15';" 2>/dev/null | grep -iE "predicates|cardinality|PREDICATES" | head -4

echo ""
echo "=========== 结果正确性校验 ==========="
echo "--- k_date_first province=广东 ---"
$D -e "SELECT COUNT(*) AS cnt, ROUND(SUM(amount)) AS total FROM k_date_first WHERE province='广东';" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- k_prov_first province=广东 ---"
$D -e "SELECT COUNT(*) AS cnt, ROUND(SUM(amount)) AS total FROM k_prov_first WHERE province='广东';" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "KEY5_DONE"

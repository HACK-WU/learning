#!/bin/bash
# 课 5：修正 Rollup 语法，并做公平对照
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 1. 先建一张专用于 Rollup 实验的表（避免影响 orders）==========="
$D -e "DROP TABLE IF EXISTS rollup_demo;" 2>&1 | grep -vE "^Warning|Using a password" | head -1
$D -e "
CREATE TABLE rollup_demo (
    province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL, category VARCHAR(32) NOT NULL,
    order_date DATE NOT NULL, user_id BIGINT NOT NULL,
    amount DECIMAL(18,2) NOT NULL, quantity INT NOT NULL
)
DUPLICATE KEY(province, city, category)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>&1 | grep -vE "^Warning|Using a password" | head -3

echo "  导入..."
S=$(date +%s)
$D -e "INSERT INTO rollup_demo SELECT province, city, category, order_date, user_id, amount, quantity FROM orders;" 2>&1 | grep -vE "^Warning|Using a password" | head -2
E=$(date +%s)
echo "  耗时: $((E-S)) 秒"
echo -n "  行数: "
$D --batch -e "SELECT COUNT(*) FROM rollup_demo;" 2>/dev/null | tail -1

echo ""
echo "=========== 2. 建 Rollup：尝试正确语法 ==========="
echo "--- 语法 A：标准写法（COUNT 需要指定列，不用 *）---"
$D -e "
CREATE MATERIALIZED VIEW rollup_pc AS
SELECT province, category, COUNT(amount) AS cnt, SUM(amount) AS total, SUM(quantity) AS qty
FROM rollup_demo GROUP BY province, category;" 2>&1 | grep -vE "^Warning|Using a password" | head -3

echo "  等待构建..."
for i in $(seq 1 24); do
  ST=$($D --batch -e "SHOW ALTER TABLE MATERIALIZED VIEW WHERE TableName='rollup_demo' ORDER BY JobId DESC LIMIT 1;" 2>/dev/null | awk -F'\t' 'NR>1{print $(NF-2)}')
  if [ -n "$ST" ]; then echo "    ${i}0 秒: $ST"; fi
  if [ "$ST" = "FINISHED" ]; then break; fi
  sleep 10
done

echo ""
echo "=========== 3. 确认 Rollup 存在 ==========="
$D -e "SHOW ALTER TABLE MATERIALIZED VIEW WHERE TableName='rollup_demo';" 2>/dev/null | grep -vE "^Warning|Using a password" | head -3

echo ""
echo "=========== 4. EXPLAIN 验证命中 Rollup ==========="
echo "--- 查询：province + category 聚合 ---"
$D -e "EXPLAIN SELECT province, category, COUNT(amount) AS cnt, SUM(amount) AS total FROM rollup_demo GROUP BY province, category;" 2>/dev/null | grep -iE "VOlapScanNode|TABLE:|cardinality=|tablets=|rollup|index" | head -6

echo ""
echo "=========== 5. 公平对照：命中 vs 强制不命中 ==========="
echo "--- 命中 Rollup（默认）---"
for i in 1 2 3; do
  S=$(date +%s.%N); $D -e "SELECT province, category, COUNT(amount) AS cnt, SUM(amount) AS total FROM rollup_demo GROUP BY province, category;" 2>/dev/null >/dev/null; E=$(date +%s.%N)
  printf '  第%d次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done

echo "--- 强制不走 Rollup ---"
$D -e "SET enable_materialized_view_rewrite=false;" 2>/dev/null >/dev/null
for i in 1 2 3; do
  S=$(date +%s.%N); $D -e "SELECT province, category, COUNT(amount) AS cnt, SUM(amount) AS total FROM rollup_demo GROUP BY province, category;" 2>/dev/null >/dev/null; E=$(date +%s.%N)
  printf '  第%d次: %.3f 秒\n' "$i" "$(echo "$E - $S" | bc)"
done
$D -e "SET enable_materialized_view_rewrite=true;" 2>/dev/null >/dev/null

echo ""
echo "=========== 6. 结果正确性（走 Rollup vs 不走，必须一致）==========="
echo "--- 走 Rollup ---"
$D -e "SELECT province, category, COUNT(amount) AS cnt, ROUND(SUM(amount)) AS total FROM rollup_demo GROUP BY province, category ORDER BY province, category LIMIT 4;" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- 不走 Rollup ---"
$D -e "SET enable_materialized_view_rewrite=false;" 2>/dev/null >/dev/null
$D -e "SELECT province, category, COUNT(amount) AS cnt, ROUND(SUM(amount)) AS total FROM rollup_demo GROUP BY province, category ORDER BY province, category LIMIT 4;" 2>/dev/null | grep -vE "^Warning|Using a password"
$D -e "SET enable_materialized_view_rewrite=true;" 2>/dev/null >/dev/null

echo ""
echo "=========== 7. 存储代价 ==========="
$D -e "SHOW DATA FROM rollup_demo;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 8. Rollup 的 tablet 数 ==========="
echo -n "  tablet 数: "
$D --batch -e "SHOW TABLETS FROM rollup_demo;" 2>/dev/null | tail -n +2 | wc -l

echo ""
echo "=========== 9. 不命中 Rollup 的查询（多一个维度）==========="
$D -e "EXPLAIN SELECT province, city, category, COUNT(amount) FROM rollup_demo GROUP BY province, city, category;" 2>/dev/null | grep -iE "VOlapScanNode|TABLE:|tablets=" | head -4

echo ""
echo "ROLLUP5B_DONE"

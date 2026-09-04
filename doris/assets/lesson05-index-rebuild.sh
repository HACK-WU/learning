#!/bin/bash
# 课 5：重建索引实验表 —— 用真实文本数据，等待索引构建完成
D="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

echo "=========== 1. 重建表，remark 用真实文本（从 category/product_id 拼）==========="
$D -e "DROP TABLE IF EXISTS idx_demo;" 2>&1 | grep -vE "^Warning|Using a password" | head -2

$D -e "
CREATE TABLE idx_demo (
    order_date DATE NOT NULL, province VARCHAR(16) NOT NULL, city VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL, amount DECIMAL(10,2) NOT NULL, quantity INT NOT NULL,
    category VARCHAR(32) NOT NULL, remark VARCHAR(255) NOT NULL
)
DUPLICATE KEY(order_date, province, city)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ('replication_num'='1');" 2>&1 | grep -vE "^Warning|Using a password" | head -3

echo "  导入（remark = 品类+日期 的真实文本）..."
S=$(date +%s)
$D -e "
INSERT INTO idx_demo
SELECT order_date, province, city, user_id, amount, quantity, category,
       CONCAT(category, ' 订单 用户', CAST(user_id AS VARCHAR), ' 于 ', CAST(order_date AS VARCHAR), ' 在 ', province, city, ' 下单')
FROM orders;" 2>&1 | grep -vE "^Warning|Using a password" | head -2
E=$(date +%s)
echo "  耗时: $((E-S)) 秒"
echo -n "  行数: "
$D --batch -e "SELECT COUNT(*) FROM idx_demo;" 2>/dev/null | tail -1

echo ""
echo "--- remark 样本 ---"
$D -e "SELECT remark FROM idx_demo LIMIT 3;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 2. 基线：无索引的 LIKE 查询 ==========="
S=$(date +%s.%N); $D -e "SELECT COUNT(*) FROM idx_demo WHERE remark LIKE '%广东深圳%';" 2>/dev/null >/dev/null; E=$(date +%s.%N)
printf '  LIKE 全表扫描: %.3f 秒\n' "$(echo "$E - $S" | bc)"
$D -e "EXPLAIN SELECT COUNT(*) FROM idx_demo WHERE remark LIKE '%广东深圳%';" 2>/dev/null | grep -iE "PREDICATES|cardinality=" | head -3

echo ""
echo "=========== 3. 存储基线（建索引前）==========="
$D -e "SHOW DATA FROM idx_demo;" 2>/dev/null | grep -vE "^Warning|Using a password" | head -3

echo ""
echo "=========== 4. 建倒排索引并等待完成 ==========="
$D -e "CREATE INDEX idx_remark ON idx_demo(remark) USING INVERTED PROPERTIES('parser'='unicode');" 2>&1 | grep -vE "^Warning|Using a password" | head -2
echo "  等待构建（轮询状态）..."
for i in $(seq 1 30); do
  ST=$($D --batch -e "SHOW ALTER TABLE COLUMN WHERE TableName='idx_demo' ORDER BY JobId DESC LIMIT 1;" 2>/dev/null | awk -F'\t' 'NR>1{print $NF}')
  echo "    ${i}0 秒: $ST"
  if [ "$ST" = "FINISHED" ]; then break; fi
  sleep 10
done

echo ""
echo "=========== 5. 倒排索引建成后：MATCH_ANY 全文检索 ==========="
$D -e "SELECT COUNT(*) FROM idx_demo WHERE remark MATCH_ANY '广东 深圳';" 2>&1 | grep -vE "^Warning|Using a password" | head -3
S=$(date +%s.%N); $D -e "SELECT COUNT(*) FROM idx_demo WHERE remark MATCH_ANY '广东 深圳';" 2>/dev/null >/dev/null; E=$(date +%s.%N)
printf '  MATCH_ANY: %.3f 秒\n' "$(echo "$E - $S" | bc)"
$D -e "EXPLAIN SELECT COUNT(*) FROM idx_demo WHERE remark MATCH_ANY '广东 深圳';" 2>/dev/null | grep -iE "PREDICATES|cardinality=|INDEX" | head -4

echo ""
echo "--- 对比 LIKE（仍然全表扫描）---"
S=$(date +%s.%N); $D -e "SELECT COUNT(*) FROM idx_demo WHERE remark LIKE '%广东深圳%';" 2>/dev/null >/dev/null; E=$(date +%s.%N)
printf '  LIKE: %.3f 秒\n' "$(echo "$E - $S" | bc)"

echo ""
echo "=========== 6. 存储代价（倒排索引占多少）==========="
$D -e "SHOW DATA FROM idx_demo;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 7. 建 NGram BloomFilter 加速 LIKE ==========="
$D -e "CREATE INDEX idx_ngram ON idx_demo(remark) USING NGRAM_BF PROPERTIES('gram_size'='3','bf_size'='1024');" 2>&1 | grep -vE "^Warning|Using a password" | head -2
echo "  等待构建..."
for i in $(seq 1 20); do
  ST=$($D --batch -e "SHOW ALTER TABLE COLUMN WHERE TableName='idx_demo' ORDER BY JobId DESC LIMIT 1;" 2>/dev/null | awk -F'\t' 'NR>1{print $NF}')
  echo "    ${i}0 秒: $ST"
  if [ "$ST" = "FINISHED" ]; then break; fi
  sleep 10
done

echo ""
echo "--- NGram 建成后 LIKE 查询 ---"
S=$(date +%s.%N); $D -e "SELECT COUNT(*) FROM idx_demo WHERE remark LIKE '%广东深圳%';" 2>/dev/null >/dev/null; E=$(date +%s.%N)
printf '  LIKE (有 NGram): %.3f 秒\n' "$(echo "$E - $S" | bc)"
$D -e "EXPLAIN SELECT COUNT(*) FROM idx_demo WHERE remark LIKE '%广东深圳%';" 2>/dev/null | grep -iE "PREDICATES|cardinality=|INDEX" | head -4

echo ""
echo "--- 再看存储代价 ---"
$D -e "SHOW DATA FROM idx_demo;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== 8. 索引清单 ==========="
$D -e "SHOW INDEX FROM idx_demo;" 2>/dev/null | grep -vE "^Warning|Using a password" | awk -F'\t' 'NR>1{print "  "$3" | "$5" | "$11" | "$13}'

echo ""
echo "IDX5B_DONE"

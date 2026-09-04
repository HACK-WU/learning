#!/bin/bash
# 课 12 评审 2：核实 chinese parser 查询为何返回 0（评审 1 的 C 节疑点）
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "=========== 1. 重建 chinese 表，逐步确认 ==========="
q "DROP TABLE IF EXISTS rv_cn2;"
q "CREATE TABLE rv_cn2 (
     ts DATETIME NULL, msg STRING NULL,
     INDEX idx_msg (msg) USING INVERTED PROPERTIES('parser' = 'chinese', 'support_phrase' = 'true')
   ) DUPLICATE KEY(ts) DISTRIBUTED BY HASH(ts) BUCKETS 1
   PROPERTIES ('replication_num' = '1');"

echo "--- INSERT 是否成功（看返回）---"
q "INSERT INTO rv_cn2 SELECT created_at, CONCAT('用户在', city, '购买了', category) FROM orders LIMIT 1000;"

echo "--- 等统计刷新 ---"
sleep 8

echo "--- 用 COUNT(*) 看行数 ---"
q "SELECT COUNT(*) AS cnt FROM rv_cn2;"
echo "--- 用 SUM(LENGTH()) 看是否真有数据（COUNT 走元数据优化，不可信）---"
q "SELECT SUM(LENGTH(msg)) AS len_sum FROM rv_cn2;"
echo "--- 看明细 ---"
q "SELECT msg FROM rv_cn2 LIMIT 3;"

echo "=========== 2. 现在再查 MATCH_ANY ==========="
q "SELECT COUNT(*) FROM rv_cn2 WHERE msg MATCH_ANY '北京';"
q "SELECT SUM(LENGTH(msg)) FROM rv_cn2 WHERE msg MATCH_ANY '北京';"

echo "=========== 3. 若上面仍返回 0，试其他中文词 ==========="
q "SELECT SUM(LENGTH(msg)) FROM rv_cn2 WHERE msg MATCH_ANY '用户';"
q "SELECT SUM(LENGTH(msg)) FROM rv_cn2 WHERE msg MATCH_ALL '用户 购买';"

echo "=========== 4. 清理 ==========="
q "DROP TABLE IF EXISTS rv_cn2;"

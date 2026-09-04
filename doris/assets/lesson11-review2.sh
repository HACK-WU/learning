#!/bin/bash
# 课 11 评审 2（pedagogy 视角）：核实正文两处可疑表述
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "===== 1. MODIFY COLUMN 对带 DEFAULT 的列：是真限制还是我写法问题？====="
q "DROP TABLE IF EXISTS rv2_a;" >/dev/null 2>&1
q "CREATE TABLE rv2_a (id INT, v INT DEFAULT '5') DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num'='1');"
echo "--- A. 改带默认值的列的类型 ---"
q "ALTER TABLE rv2_a MODIFY COLUMN v BIGINT;" 2>&1 | sed 's/^/  /'
echo "--- B. 改不带默认值的列的类型 ---"
q "ALTER TABLE rv2_a MODIFY COLUMN id BIGINT;" 2>&1 | sed 's/^/  /'
q "DESC rv2_a;" | sed 's/^/  /'
echo "--- C. 带默认值 + 显式写 DEFAULT NULL ---"
q "ALTER TABLE rv2_a MODIFY COLUMN v BIGINT DEFAULT NULL;" 2>&1 | sed 's/^/  /'
q "DESC rv2_a;" | sed 's/^/  /'
echo "--- D. 不带默认值的列加宽（确认可行）---"
q "DROP TABLE IF EXISTS rv2_b;" >/dev/null 2>&1
q "CREATE TABLE rv2_b (id INT, v INT) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num'='1');"
q "INSERT INTO rv2_b SELECT number, number FROM numbers('number'='10000');"
sleep 2
q "ALTER TABLE rv2_b MODIFY COLUMN v BIGINT;" 2>&1 | sed 's/^/  /'
q "DESC rv2_b;" | grep -E "^v" | sed 's/^/  /'

echo ""
echo "===== 2. ORDER BY 写漏列：为什么这次没复现？====="
q "DROP TABLE IF EXISTS rv2_c;" >/dev/null 2>&1
q "CREATE TABLE rv2_c (id INT, dt DATE, v INT) DUPLICATE KEY(id, dt)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num'='1');"
q "INSERT INTO rv2_c SELECT number, '2026-01-01', number FROM numbers('number'='10000');"
sleep 2
echo "--- 2a. 漏掉 v（3 列只写 2 列）---"
q "ALTER TABLE rv2_c ORDER BY (dt, id);" 2>&1 | sed 's/^/  /'
echo "--- 2b. 写全 3 列 ---"
q "ALTER TABLE rv2_c ORDER BY (dt, id, v);" 2>&1 | sed 's/^/  /'
sleep 2
q "DESC rv2_c;" | sed 's/^/  /'
echo "--- 2c. 再试一次漏列（此时 Key 已变成 dt,id,v）---"
q "ALTER TABLE rv2_c ORDER BY (id, dt);" 2>&1 | sed 's/^/  /'
echo "--- 2d. 用一张只有 2 列的表测 ---"
q "DROP TABLE IF EXISTS rv2_d;" >/dev/null 2>&1
q "CREATE TABLE rv2_d (id INT, v INT) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num'='1');"
q "INSERT INTO rv2_d SELECT number, number FROM numbers('number'='10000');"
sleep 2
q "ALTER TABLE rv2_d ORDER BY (id, v);" 2>&1 | sed 's/^/  /'
q "ALTER TABLE rv2_d ORDER BY (v, id);" 2>&1 | sed 's/^/  /'
sleep 2
q "DESC rv2_d;" | sed 's/^/  /'

echo ""
echo "===== 3. 复查：正文用的 sc_light 表当时有几列？====="
q "DROP TABLE IF EXISTS rv2_e;" >/dev/null 2>&1
q "CREATE TABLE rv2_e (id INT, dt DATE, amount DECIMAL(10,2)) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 4
   PROPERTIES ('replication_num'='1', 'light_schema_change'='true');"
echo "--- 加 3 列后（模拟评审 1 里 rv_light 的状态）---"
q "ALTER TABLE rv2_e ADD COLUMN c2 INT DEFAULT '2' AFTER amount;" >/dev/null 2>&1
q "ALTER TABLE rv2_e RENAME COLUMN c2 renamed_c2;" >/dev/null 2>&1
q "DESC rv2_e;" | sed 's/^/  /'
echo "--- 此时 ORDER BY 只写 2 列（共 4 列）---"
q "ALTER TABLE rv2_e ORDER BY (dt, id);" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 清理 ====="
for t in rv2_a rv2_b rv2_c rv2_d rv2_e; do
  q "DROP TABLE IF EXISTS $t;" >/dev/null 2>&1
done
echo "  done"

#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "=== 1. 建 3 副本表（关键验证：副本能否真的分布到两台 BE） ==="
runq "DROP TABLE IF EXISTS repl3;"
runq "CREATE TABLE repl3 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '3');"

echo ""
echo "=== 2. 插数据（注意：3 副本但只有 2 台 BE，应失败或只成功部分） ==="
runq "INSERT INTO repl3 SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;"

echo ""
echo "=== 3. 查数据条数 ==="
runq "SELECT COUNT(*) FROM repl3;"

echo ""
echo "=== 4. 看 tablet 分布 ==="
runq "SHOW TABLETS FROM repl3;" | head -12

echo ""
echo "=== 5. 建 2 副本表做对照 ==="
runq "DROP TABLE IF EXISTS repl2;"
runq "CREATE TABLE repl2 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '2');"
runq "INSERT INTO repl2 SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;"
runq "SELECT COUNT(*) FROM repl2;"

echo ""
echo "=== 6. 两表 tablet 分布对比 ==="
echo "--- repl3 ---"
runq "SHOW TABLETS FROM repl3;" | awk 'NR>1{print $3}' | sort | uniq -c
echo "--- repl2 ---"
runq "SHOW TABLETS FROM repl2;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "=== 7. SHOW PROC /backends 看 tablet 数变化 ==="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW PROC '/backends'\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|TabletNum|Alive"

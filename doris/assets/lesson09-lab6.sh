#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. 验证：ALTER 修改副本数，看是否补齐到 12 ==="
runq "ALTER TABLE ha_demo SET ('replication_num' = '2');"
echo "--- 等 60 秒 ---"
sleep 60
runq "SHOW TABLETS FROM ha_demo;" | wc -l
runq "SHOW TABLETS FROM ha_demo;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "=== 2. 换个思路：建 1 副本表，再 ALTER 到 2 副本，看是否补 ==="
runq "DROP TABLE IF EXISTS ha_demo2;"
runq "CREATE TABLE ha_demo2 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO ha_demo2 SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;"
echo "--- 1 副本时：6 个 tablet 全在一台 BE ---"
runq "SHOW TABLETS FROM ha_demo2;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "--- ALTER 到 2 副本 ---"
runq "ALTER TABLE ha_demo2 MODIFY DISTRIBUTION DISTRIBUTED BY HASH(id) BUCKETS 6;"
runq "ALTER TABLE ha_demo2 SET ('replication_num' = '2');"
sleep 75
echo "--- 现在副本分布（应补到 12：每台 BE 各 6） ---"
runq "SHOW TABLETS FROM ha_demo2;" | wc -l
runq "SHOW TABLETS FROM ha_demo2;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "=== 3. 关键实验：现在停 BE2，ha_demo2 还能查吗？ ==="
runq "SELECT COUNT(*), SUM(amount) FROM ha_demo2;" 2>&1
BE2PID=$(docker exec doris-learn bash -c "ps aux | grep '[b]e2/lib/doris_be' | awk '{print \$2}'")
echo "--- kill BE2 (pid=$BE2PID) ---"
docker exec doris-learn bash -c "kill -9 $BE2PID" 2>&1
sleep 30
echo "--- 查询 ha_demo2（2 副本） ---"
runq "SELECT COUNT(*), SUM(amount) FROM ha_demo2;" 2>&1
echo "--- 查询 repl3（1 副本，部分在 BE2） ---"
runq "SELECT COUNT(*) FROM repl3;" 2>&1
echo "--- 查询 orders（1 副本，全在 BE1） ---"
runq "SELECT COUNT(*) FROM orders;" 2>&1

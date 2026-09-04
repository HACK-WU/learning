#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. 恢复 BE2 ==="
docker exec -d doris-learn bash /opt/be2/launch.sh
sleep 40
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum"

echo ""
echo "=== 2. 等副本修复完成 ==="
sleep 45
$FE -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 | grep -vE "^Warning|Using a password" | head -6

echo ""
echo "=== 3. 建一张'真 2 副本'表：确保每个 tablet 在两台 BE 上都有副本 ==="
runq "DROP TABLE IF EXISTS ha_demo;"
runq "CREATE TABLE ha_demo (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '2');"
runq "INSERT INTO ha_demo SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;"

echo ""
echo "=== 4. 关键：确认每个 tablet 在两台 BE 上都有一份 ==="
echo "（6 个 tablet，每个应有 2 个副本，共 12 行）"
runq "SHOW TABLETS FROM ha_demo;" | wc -l
runq "SHOW TABLETS FROM ha_demo;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "=== 5. 等副本补齐到位（2 副本 × 6 tablet = 12） ==="
sleep 60
runq "SHOW TABLETS FROM ha_demo;" | wc -l
runq "SHOW TABLETS FROM ha_demo;" | awk 'NR>1{print $3}' | sort | uniq -c
runq "SELECT COUNT(*) FROM ha_demo;"

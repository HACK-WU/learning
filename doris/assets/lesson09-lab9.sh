#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. 副本数对存储成本的影响（单副本基准） ==="
runq "DROP TABLE IF EXISTS cost1;"
runq "CREATE TABLE cost1 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO cost1 SELECT user_id % 1000000, province, amount FROM orders LIMIT 1000000;"
sleep 45
echo "--- cost1 (1 副本, 100 万行) 数据大小 ---"
runq "SHOW DATA FROM cost1;"

echo ""
echo "=== 2. 扩缩容限速相关 FE 配置 ==="
$FE -e "SHOW FRONTEND CONFIG LIKE '%balance_slot%';" 2>&1 | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE '%be_rebalancer%';" 2>&1 | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE '%partition_rebalance%';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 3. BE 关键监控（tablet/副本/容量） ==="
$FE -e "SHOW PROC '/backends'\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|DataUsedCapacity|TotalCapacity|UsedPct|RunningTasks|CpuCores"

echo ""
echo "=== 4. 副本调度相关配置 ==="
$FE -e "SHOW FRONTEND CONFIG LIKE '%repair%';" 2>&1 | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE '%tablet%';" 2>&1 | grep -vE "^Warning|Using a password" | head -20

echo ""
echo "=== 5. 心跳与超时配置（解释宕机检测时间） ==="
$FE -e "SHOW FRONTEND CONFIG LIKE '%heartbeat%';" 2>&1 | grep -vE "^Warning|Using a password"

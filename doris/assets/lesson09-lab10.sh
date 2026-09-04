#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. 存储成本实测（等 SHOW DATA 统计刷新） ==="
echo "--- cost1: 1 副本 100 万行 ---"
runq "SHOW DATA FROM cost1;"
echo "--- ha_demo: 2 副本 5 万行 ---"
runq "SHOW DATA FROM ha_demo;"
echo "--- repl3: 3副本声明 5 万行 ---"
runq "SHOW DATA FROM repl3;"

echo ""
echo "=== 2. Tablet 结构讲解素材：orders 的分区/分桶/副本 ==="
runq "SHOW PARTITIONS FROM orders;" | head -4
echo ""
echo "--- orders 的 tablet 明细（前 4 个） ---"
runq "SHOW TABLETS FROM orders LIMIT 4;" | awk 'NR==1 || NR>1 {print $1, $2, $3, $6, $11, $12}'

echo ""
echo "=== 3. 全库 tablet/replica 统计（讲 Tablet 与 Replica 的关系） ==="
$FE -e "SHOW PROC '/statistic';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 4. 副本状态机：看一个 tablet 的完整副本列表 ==="
TID=$(runq "SHOW TABLETS FROM ha_demo LIMIT 1;" | awk 'NR==2{print $1}')
echo "tablet = $TID"
runq "SHOW TABLET $TID\G" 2>&1 | grep -E "TabletId|BackendId|State|Version|RowCount|DataSize" | head -20

echo ""
echo "=== 5. BE 磁盘层级视图（讲副本落在哪块盘） ==="
$FE -e "SHOW PROC '/backends/1788336157417';" 2>&1 | grep -vE "^Warning|Using a password" | head -8

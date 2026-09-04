#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. 确认 BE2 当前状态 ==="
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|SystemDecommissioned"

echo ""
echo "=== 2. 重启 BE2（lab6 里被 kill 了） ==="
docker exec -d doris-learn bash /opt/be2/launch.sh
sleep 40
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|SystemDecommissioned"

echo ""
echo "=== 3. 执行 DECOMMISSION（缩容） ==="
$FE -e "ALTER SYSTEM DECOMMISSION BACKEND '127.0.0.1:19050';" 2>&1 | grep -vE "^Warning|Using a password"
sleep 10
echo "--- 缩容中状态 ---"
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|SystemDecommissioned"

echo ""
echo "=== 4. 等 120 秒看 tablet 是否迁走 ==="
sleep 120
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|SystemDecommissioned|ErrMsg"

echo ""
echo "=== 5. 调度历史 ==="
$FE -e "SHOW PROC '/cluster_balance';" 2>&1 | grep -vE "^Warning|Using a password"

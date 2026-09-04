#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 0. 前置：确保 repl3 有真实数据落在 BE2 ==="
runq "SELECT COUNT(*) FROM repl3;"
runq "SHOW TABLETS FROM repl3;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "=== 1. 停掉 BE2（模拟宕机） ==="
BE2PID=$(docker exec doris-learn bash -c "ps aux | grep '[b]e2/lib/doris_be' | awk '{print \$2}'")
echo "BE2 PID = $BE2PID"
docker exec doris-learn bash -c "kill -9 $BE2PID 2>&1; echo killed" 2>&1

echo ""
echo "=== 2. 立刻查 SHOW BACKENDS（心跳还没超时，应仍 Alive 或刚转 false） ==="
sleep 3
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|ErrMsg"

echo ""
echo "=== 3. 关键验证：此刻查询还能跑吗？（心跳窗口内） ==="
echo "--- 查 repl3（数据在 BE2 上的 tablet） ---"
runq "SELECT COUNT(*), SUM(amount) FROM repl3;" 2>&1
echo "--- 查 orders（数据全在 BE1） ---"
runq "SELECT COUNT(*) FROM orders;" 2>&1

echo ""
echo "=== 4. 等心跳超时（默认 15 秒）后再看 ==="
sleep 25
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|ErrMsg|TabletNum"

echo ""
echo "=== 5. 宕机后查询还能跑吗？ ==="
echo "--- repl3（部分 tablet 在 BE2） ---"
runq "SELECT COUNT(*), SUM(amount) FROM repl3;" 2>&1

echo ""
echo "=== 6. 副本健康状态（应出现 ReplicaMissing） ==="
$FE -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 | grep -vE "^Warning|Using a password" | head -6

echo ""
echo "=== 7. 调度器是否在抢修 ==="
$FE -e "SHOW PROC '/cluster_balance';" 2>&1 | grep -vE "^Warning|Using a password"

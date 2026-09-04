#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. 打开均衡开关 ==="
$FE -e "ADMIN SET FRONTEND CONFIG ('disable_balance' = 'false');" 2>&1 | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE 'disable_balance';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 2. 记录均衡前的 tablet 分布 ==="
$FE -e "SHOW PROC '/backends'\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|TabletNum" 
echo "--- 上面两个 BackendId 分别对应 9050(BE1) 与 19050(BE2) ---"

echo ""
echo "=== 3. 等 90 秒观察均衡是否发生 ==="
sleep 90
$FE -e "SHOW PROC '/backends'\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|TabletNum"

echo ""
echo "=== 4. 副本是否在补齐（repl3 应补到 3 副本/tablet） ==="
runq "SHOW TABLETS FROM repl3;" | awk 'NR>1{print $3}' | sort | uniq -c
runq "SHOW TABLETS FROM repl3;" | wc -l

echo ""
echo "=== 5. 找 4.1.3 正确的调度视图 ==="
for p in "/cluster_balance" "/cluster_balance/scheduler" "/cluster_balance/working_slots" "/statistic" "/cluster_health"; do
  echo "--- SHOW PROC '$p' ---"
  $FE -e "SHOW PROC '$p';" 2>&1 | grep -vE "^Warning|Using a password" | head -8
done

echo ""
echo "=== 6. 副本健康总览（TabletChecker） ==="
$FE -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 | grep -vE "^Warning|Using a password" | head -6

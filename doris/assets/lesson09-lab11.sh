#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. 当前 BE2 状态（lab7 已 DECOMMISSION） ==="
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|SystemDecommissioned"

echo ""
echo "=== 2. 关键验证：DECOMMISSION 期间在线查询是否受影响 ==="
echo "--- 连续查 5 次 orders（数据全在 BE1，模拟在线业务） ---"
for i in 1 2 3 4 5; do
  START=$(date +%s%N)
  runq "SELECT province, SUM(amount) FROM orders GROUP BY province ORDER BY province LIMIT 3;" > /dev/null 2>&1
  END=$(date +%s%N)
  MS=$(( (END - START) / 1000000 ))
  echo "第 $i 次: ${MS} ms"
done

echo ""
echo "=== 3. 取消 DECOMMISSION（CANCEL）验证可逆性 ==="
$FE -e "CANCEL DECOMMISSION BACKEND '127.0.0.1:19050';" 2>&1 | grep -vE "^Warning|Using a password"
sleep 5
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|SystemDecommissioned"

echo ""
echo "=== 4. 重新加回（ADD BACKEND 幂等性验证） ==="
$FE -e "ALTER SYSTEM ADD BACKEND '127.0.0.1:19050';" 2>&1 | grep -vE "^Warning|Using a password"
sleep 3
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|SystemDecommissioned|TabletNum"

echo ""
echo "=== 5. DROP BACKEND 与 DECOMMISSION 的区别 ==="
$FE -e "ALTER SYSTEM DROP BACKEND '127.0.0.1:19050';" 2>&1 | grep -vE "^Warning|Using a password"
sleep 3
echo "--- DROP 后（应彻底消失） ---"
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive"

echo ""
echo "=== 6. 重新加回，恢复双节点 ==="
$FE -e "ALTER SYSTEM ADD BACKEND '127.0.0.1:19050';" 2>&1 | grep -vE "^Warning|Using a password"
sleep 20
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|SystemDecommissioned"

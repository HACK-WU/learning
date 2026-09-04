#!/bin/bash
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== 1. FE 角色现状 ==="
$FE -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "Name|Host|Role|IsMaster|Join|Alive|ReplayedJournalId|EditLogPort"

echo ""
echo "=== 2. 尝试 ADD FOLLOWER（同 IP 不同端口） ==="
$FE -e "ALTER SYSTEM ADD FOLLOWER '127.0.0.1:9011';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 3. 尝试 ADD OBSERVER ==="
$FE -e "ALTER SYSTEM ADD OBSERVER '127.0.0.1:9012';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 4. 看 FE 列表 ==="
$FE -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "Name|Host|Role|IsMaster|Join|Alive|EditLogPort"

echo ""
echo "=== 5. FE 元数据相关视图 ==="
echo "--- /frontends ---"
$FE -e "SHOW PROC '/frontends'\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "Name|Role|IsMaster|Alive|Join" | head -12

echo ""
echo "=== 6. 清理误加的 FE（DROP 试试） ==="
$FE -e "ALTER SYSTEM DROP FOLLOWER '127.0.0.1:9011';" 2>&1 | grep -vE "^Warning|Using a password"
$FE -e "ALTER SYSTEM DROP OBSERVER '127.0.0.1:9012';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 7. 最终 FE 列表 ==="
$FE -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "Role|IsMaster|Alive|Host"

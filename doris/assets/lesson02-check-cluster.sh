#!/bin/bash
# 课 2：验证 FE / BE 存活状态
MYSQL="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=== SHOW FRONTENDS ==="
$MYSQL -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== SHOW BACKENDS ==="
$MYSQL -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 精简版：Alive 状态 ==="
$MYSQL --batch -e "SHOW FRONTENDS;" 2>/dev/null | awk -F'\t' 'NR==1{print "FE Alive 列位置待定"} {print}' | head -5

echo ""
echo "=== 版本信息 ==="
$MYSQL --batch -e "SELECT VERSION();" 2>/dev/null

echo ""
echo "=== 帮助命令是否存在 ==="
$MYSQL --batch -e "SHOW PROC '/frontends';" 2>&1 | head -5

echo ""
echo "CHECK_DONE"

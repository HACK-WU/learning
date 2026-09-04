#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "=== 1. 等 60 秒，看副本是否自动补齐 ==="
sleep 60

echo "--- repl3 副本数（应为 6 tablet × 3 = 18，或受限于 2 台 BE） ---"
runq "SHOW TABLETS FROM repl3;" | wc -l
runq "SHOW TABLETS FROM repl3;" | awk 'NR>1{print $3}' | sort | uniq -c

echo "--- repl2 副本数（应为 6 × 2 = 12） ---"
runq "SHOW TABLETS FROM repl2;" | wc -l
runq "SHOW TABLETS FROM repl2;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "=== 2. 副本健康状态（关键：有没有 unhealthy / missing） ==="
runq "ADMIN SHOW REPLICA STATUS FROM repl3;" | grep -vE "^Warning" | head -20

echo ""
echo "=== 3. 各 BE 的 tablet 数（看均衡是否发生） ==="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW PROC '/backends'\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -E "BackendId|HeartbeatPort|TabletNum|Alive|DataUsedCapacity"

echo ""
echo "=== 4. 查 tablet 调度任务是否在跑 ==="
runq "SHOW PROC '/cluster_balance/sched_stat';" 2>&1 | head -10

echo ""
echo "=== 5. 关键变量：均衡开关 ==="
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW FRONTEND CONFIG LIKE '%balance%';" 2>&1 | grep -vE "^Warning|Using a password"

#!/bin/bash
# 课 9 清理：删除实验表、恢复配置、可选移除 BE2
# 用法：bash lesson09-cleanup.sh
#
# 删的对象：cost1、repl3、ha_demo、ha_demo2
# 恢复的配置：disable_balance 改回 true（默认值）
# 可选：加 --remove-be2 参数会同时停掉并移除第二个 BE

MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "=========================================="
echo " 课 9 清理"
echo "=========================================="

echo ""
echo "========== 1. 删除实验表 =========="
for t in cost1 repl3 ha_demo ha_demo2; do
  echo "DROP TABLE IF EXISTS $t"
  runq "DROP TABLE IF EXISTS $t;"
done

echo ""
echo "========== 2. 恢复 FE 配置 =========="
echo "disable_balance 改回默认值 true"
$FE -e "ADMIN SET FRONTEND CONFIG ('disable_balance' = 'true');" 2>&1 \
  | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE 'disable_balance';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "========== 3. 确认清理结果 =========="
echo "--- 剩余表 ---"
runq "SHOW TABLES;" | grep -E "cost1|repl3|ha_demo" || echo "✅ 实验表已全部删除"

echo ""
echo "--- 集群健康 ---"
$FE -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "========== 4. 是否移除 BE2 =========="
if [ "$1" = "--remove-be2" ]; then
  echo "收到 --remove-be2，开始移除第二个 BE"

  echo ""
  echo "--- 4.1 安全摘除（先迁数据）---"
  $FE -e "ALTER SYSTEM DECOMMISSION BACKEND '127.0.0.1:19050';" 2>&1 \
    | grep -vE "^Warning|Using a password"
  echo "等待 60 秒让数据迁走..."
  sleep 60
  $FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
    | grep -E "BackendId|HeartbeatPort|TabletNum|SystemDecommissioned"

  echo ""
  echo "--- 4.2 停掉 BE2 进程 ---"
  BE2PID=$(docker exec doris-learn bash -c "ps aux | grep '[b]e2/lib/doris_be' | awk '{print \$2}'")
  if [ -n "$BE2PID" ]; then
    docker exec doris-learn bash -c "kill -9 $BE2PID" 2>&1
    echo "已停掉 BE2 进程 (pid=$BE2PID)"
  else
    echo "BE2 进程不存在，跳过"
  fi

  echo ""
  echo "--- 4.3 从集群移除（DECOMMISSION 完成后节点会自动消失）---"
  sleep 20
  $FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
    | grep -E "BackendId|HeartbeatPort|Alive"

  echo ""
  echo "--- 4.4 清理目录 ---"
  docker exec doris-learn bash -c "rm -rf /opt/be2 && echo '已删除 /opt/be2'" 2>&1

  echo ""
  echo "✅ BE2 已移除，集群恢复为单节点"
else
  echo "未指定 --remove-be2，保留第二个 BE"
  echo "（保留 BE2 可以让后续课程继续做多节点实验）"
  echo ""
  echo "--- 当前集群 ---"
  $FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
    | grep -E "BackendId|HeartbeatPort|Alive|TabletNum"
  echo ""
  echo "如需移除：bash lesson09-cleanup.sh --remove-be2"
fi

echo ""
echo "=========================================="
echo " 清理完成"
echo "=========================================="

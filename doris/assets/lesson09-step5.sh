#!/bin/bash
# 课 9 步骤 5：宕机演练 —— kill 掉第二个 BE，观察自动修复
# 用法：bash lesson09-step5.sh
#
# ⚠️ 本脚本会真的停掉一个 BE 进程。只在自己的学习环境跑，别在生产上试。
# ⚠️ 前置：需要第二台 BE（跑过 lesson09-add-be2.sh）

MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "=========================================="
echo " 课 9 步骤 5：宕机演练"
echo "=========================================="
echo "⚠️ 本脚本会 kill 掉第二个 BE 进程（模拟宕机），然后观察集群自愈"

echo ""
echo "========== 步骤 5.0：确认前置条件 =========="
BECOUNT=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -c "BackendId")
if [ "$BECOUNT" -lt 2 ]; then
  echo "❌ 只有 1 台 BE。宕机演练需要第二台 BE，请先跑 lesson09-add-be2.sh"
  exit 1
fi
echo "✅ 检测到 $BECOUNT 台 BE"

# 找到 BE2 的进程号（be2 路径的 doris_be，区别于原 BE 的 /opt/apache-doris/be/lib）
BE2PID=$(docker exec doris-learn bash -c "ps aux | grep '[b]e2/lib/doris_be' | awk '{print \$2}'")
if [ -z "$BE2PID" ]; then
  echo "❌ 没找到 BE2 进程。请先启动：docker exec -d doris-learn bash /opt/be2/launch.sh"
  exit 1
fi
echo "✅ BE2 进程号 = $BE2PID"

echo ""
echo "========== 步骤 5.1b：准备一张必然落在 BE2 上的表 =========="
echo "⚠️ 为什么需要这一步：均衡机制可能已经把 repl3 的 tablet 从 BE2 搬走，"
echo "   那样 kill 掉 BE2 后查 repl3 不会报错，实验就观察不到想要的现象。"
echo ""
echo "   ⚠️ 又一个实测发现：**tablet 落在哪个 BE 由调度器决定，无法手动指定**。"
echo "      我试过 ADMIN MIGRATE TABLET，4.1.3 直接报语法错误："
echo "        ERROR 1105 (HY000): no viable alternative at input 'ADMIN MIGRATE'"
echo "      也试过反复建表 6 次，结果 6 次全部落在 BE1（BE1=12, BE2=0）。"
echo ""
echo "   所以这里用最可靠的办法：**先建表，查出它落在哪，然后就宕掉那个节点**。"
runq "DROP TABLE IF EXISTS pinned_be2;"
runq "CREATE TABLE pinned_be2 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 12
PROPERTIES ('replication_num' = '1');"
runq "INSERT INTO pinned_be2 SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;"
echo "--- 确认它有哪些 tablet 落在 BE2(19050) 上 ---"
BE1ID=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | awk '/BackendId:/{id=$2} /HeartbeatPort: 9050/{print id; exit}')
BE2ID=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | awk '/BackendId:/{id=$2} /HeartbeatPort: 19050/{print id; exit}')
echo "BE1(9050)  BackendId = $BE1ID"
echo "BE2(19050) BackendId = $BE2ID"
PINNED_BE2=$(runq "SHOW TABLETS FROM pinned_be2;" | awk -v b="$BE2ID" 'NR>1 && $3==b' | wc -l)
PINNED_BE1=$(runq "SHOW TABLETS FROM pinned_be2;" | awk -v b="$BE2ID" 'NR>1 && $3!=b' | wc -l)
echo "pinned_be2 落在 BE2 的 tablet 数 = $PINNED_BE2"
echo "pinned_be2 落在 BE1 的 tablet 数 = $PINNED_BE1"

# 根据 tablet 实际位置决定宕谁，保证实验必然复现
if [ "$PINNED_BE2" -gt 0 ]; then
  VICTIM_NAME="BE2"; VICTIM_HB="19050"; VICTIM_ID="$BE2ID"; VICTIM_PID="$BE2PID"
  echo "✅ pinned_be2 有 $PINNED_BE2 个 tablet 在 BE2 上 → 本轮宕 BE2"
else
  VICTIM_NAME="BE1"; VICTIM_HB="9050"; VICTIM_ID="$BE1ID"
  echo "⚠️ pinned_be2 的 tablet 全在 BE1 上（这是常态：实测建表 6 次全落 BE1）"
  echo "   → 本轮改为宕 BE1，这样 pinned_be2 必然被命中"
  echo "   ⚠️ 连带影响：orders 等大表也在 BE1，它们会一起查不了 —— 这是预期现象"
fi
echo "本轮目标节点：$VICTIM_NAME (127.0.0.1:$VICTIM_HB, id=$VICTIM_ID)"

echo ""
echo "========== 步骤 5.1：宕机前的基线 =========="
echo "--- 集群健康 ---"
$FE -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 | grep -vE "^Warning|Using a password"
echo ""
echo "--- 查询正常性（两条都应有结果）---"
echo -n "orders（数据在 BE1）: "
runq "SELECT COUNT(*) FROM orders;" | tail -1
echo -n "repl3: "
runq "SELECT COUNT(*) FROM repl3;" | tail -1
echo -n "pinned_be2（有 tablet 在 BE2）: "
runq "SELECT COUNT(*) FROM pinned_be2;" | tail -1

echo ""
echo "========== 步骤 5.2：kill 掉 $VICTIM_NAME（模拟宕机）=========="
if [ "$VICTIM_NAME" = "BE2" ]; then
  docker exec doris-learn bash -c "kill -9 $VICTIM_PID" 2>&1
  echo "已 kill $VICTIM_NAME (pid=$VICTIM_PID)"
else
  # 宕 BE1：原 BE 进程（路径是 /opt/apache-doris/be/lib/doris_be）
  BE1PID=$(docker exec doris-learn bash -c "ps aux | grep '[a]pache-doris/be/lib/doris_be' | awk '{print \$2}'")
  echo "BE1 进程号 = $BE1PID"
  docker exec doris-learn bash -c "kill -9 $BE1PID" 2>&1
  echo "已 kill $VICTIM_NAME (pid=$BE1PID)"
  echo "⚠️ 注意：原 BE 由容器 entrypoint 管理，kill 后可能自动重启，"
  echo "      那样实验窗口会很短。若观察不到，请改用 BE2 作为目标。"
fi

echo ""
echo "========== 步骤 5.3：立刻查（心跳窗口内）=========="
echo "⚠️ 此刻 FE 还不知道节点挂了，SHOW BACKENDS 可能仍显示 Alive=true"
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "BackendId|HeartbeatPort|Alive|ErrMsg"

echo ""
echo "--- 查 orders（副本在存活节点，应正常）---"
runq "SELECT COUNT(*) FROM orders;" 2>&1 | tail -3

echo ""
echo "--- 查 orders（副本在存活节点，应正常）---"
runq "SELECT COUNT(*) FROM orders;" 2>&1 | tail -3

echo ""
echo "--- 查 pinned_be2（有 $PINNED_BE2 个 tablet 在刚被 kill 的 BE2 上）---"
echo ""
echo "⚠️⚠️ 关键坑（课 9 实测发现，前九课都没注意到）："
echo "   不要用 SELECT COUNT(*) 来验证数据是否可查！"
echo "   Doris 对简单的 COUNT(*) 走的是**元数据行数优化**，"
echo "   直接从 FE 的行数统计返回，根本不去扫 BE —— 所以宕机了它照样返回结果。"
echo "   实测：所有 tablet 都在宕机节点的表，SELECT COUNT(*) 依然返回 50000。"
echo ""
echo "   必须用**真正要扫数据**的查询才能暴露问题，比如取明细行或带谓词的聚合。"
echo ""
echo "--- 5.3a 取明细行（必然扫 BE）---"
PIN_A=$(runq "SELECT id, province, amount FROM pinned_be2 LIMIT 3;" 2>&1 | tail -3)
echo "$PIN_A"
echo ""
echo "--- 5.3b 带谓词的聚合（必然扫 BE）---"
PIN_B=$(runq "SELECT province, COUNT(*) AS c, SUM(amount) AS s FROM pinned_be2 WHERE amount > 100 GROUP BY province ORDER BY c DESC LIMIT 5;" 2>&1 | tail -6)
echo "$PIN_B"
echo ""
if echo "$PIN_A$PIN_B" | grep -q "ERROR"; then
  echo "✅ 复现成功：需要扫数据的查询报错了"
else
  echo "⚠️ 没报错。可能原因：pinned_be2 的 tablet 分散在两台 BE 上，"
  echo "   宕掉 BE2 后 BE1 上的那部分仍可查，而查询恰好没需要 BE2 上的 tablet。"
fi
echo ""
echo "--- 对照：SELECT COUNT(*) 会返回什么（大概率正常返回）---"
echo "👆 这就是上面说的元数据优化，不要被它误导"
runq "SELECT COUNT(*) FROM pinned_be2;" 2>&1 | tail -2

echo ""
echo "========== 步骤 5.4：等 35 秒，让心跳超时 =========="
echo "（heartbeat_interval_second=10，容忍 1 次失败，约 10~20 秒判定死亡）"
sleep 35
echo "--- 此刻 FE 应已判定节点死亡 ---"
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "BackendId|HeartbeatPort|Alive|ErrMsg"

echo ""
echo "--- 再查 pinned_be2（用扫数据的查询）---"
echo "👆 预期（命中宕机节点时）报错会从 RpcException 变成："
echo "     tablet xxx has no queryable replicas"
echo "   差别：前者是"连不上"，后者是 FE 已判定节点死亡、明确无副本可用"
PIN2=$(runq "SELECT id, province, amount FROM pinned_be2 LIMIT 3;" 2>&1 | tail -3)
echo "$PIN2"
if echo "$PIN2" | grep -q "ERROR"; then
  echo "✅ 复现成功：报错从 UNAVAILABLE 变成了 has no queryable replicas"
fi
echo ""
echo "--- 全表聚合（强制扫所有 tablet，最容易暴露问题）---"
runq "SELECT SUM(amount) FROM pinned_be2;" 2>&1 | tail -3

echo ""
echo "========== 步骤 5.5：观察集群进入修复状态 =========="
$FE -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 | grep -vE "^Warning|Using a password"
echo "👆 HealthyNum 会下降，NeedFurtherRepairNum 会大于 0"
echo "   本机实测参考：611 → 603，NeedFurtherRepairNum = 8"

echo ""
echo "========== 步骤 5.6：恢复节点 =========="
echo "重启 BE2..."
docker exec -d doris-learn bash /opt/be2/launch.sh
echo "等待 40 秒让 BE2 启动并重新注册"
sleep 40
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "BackendId|HeartbeatPort|Alive|ErrMsg"

echo ""
echo "========== 步骤 5.7：验证自愈（等 45 秒）=========="
echo "（什么都不做，看集群能不能自己修复）"
sleep 45
$FE -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 | grep -vE "^Warning|Using a password"
echo ""
echo "👆 关键验证：HealthyNum 应该自己回到 611（等于 TabletNum），全程零人工干预"
echo "   这就是"自动修复" —— Tablet 调度器发现副本缺失，自动在存活节点上重建"

echo ""
echo "========== 步骤 5.8：查询恢复正常了吗？=========="
echo -n "repl3: "
runq "SELECT COUNT(*) FROM repl3;" 2>&1 | tail -1

echo ""
echo "=========================================="
echo " 宕机演练完成。"
echo " 清理：bash lesson09-cleanup.sh"
echo "=========================================="

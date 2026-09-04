#!/bin/bash
# 课 9 步骤 4：知识点 3 —— 扩缩容与数据均衡
# 用法：bash lesson09-step4.sh
#
# 前置：需要第二台 BE。只有 1 台 BE 时请先跑 lesson09-add-be2.sh
# 本脚本会：打开均衡开关 → 观察迁移 → DECOMMISSION → CANCEL → 演示 DROP 被拒

MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

BE2_HOST="127.0.0.1"
BE2_HB="19050"

echo "=========================================="
echo " 课 9 步骤 4：扩缩容与数据均衡"
echo "=========================================="

echo ""
echo "========== 步骤 4.0：确认有两个 BE =========="
BECOUNT=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -c "BackendId")
echo "检测到 BE 数量 = $BECOUNT"
if [ "$BECOUNT" -lt 2 ]; then
  echo "❌ 只有 1 台 BE，无法做扩缩容实验。"
  echo "   请先执行：bash lesson09-add-be2.sh"
  exit 1
fi
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "BackendId|HeartbeatPort|Alive|TabletNum|SystemDecommissioned"

echo ""
echo "========== 步骤 4.1：扩容前先看均衡开关 =========="
echo "⚠️ 课 9 实测：disable_balance 出厂默认是 true（均衡默认关闭！）"
echo "   但如果你之前打开过（比如跑过本脚本、或课 9 正文实验），它现在可能已经是 false"
CUR_BAL=$($FE -e "SHOW FRONTEND CONFIG LIKE 'disable_balance';" 2>&1 \
  | grep -vE "^Warning|Using a password" | awk 'NR==2{print $2}')
echo "当前值 = $CUR_BAL"
$FE -e "SHOW FRONTEND CONFIG LIKE 'disable_balance';" 2>&1 | grep -vE "^Warning|Using a password"
if [ "$CUR_BAL" = "true" ]; then
  echo "→ 均衡当前是关闭的，步骤 4.2 会打开它"
else
  echo "→ 均衡已经是打开的（可能之前跑过本脚本）。这不影响后面的实验，"
  echo "  只是步骤 4.3 观察到的迁移量可能比第一次跑时少。"
fi

echo ""
echo "--- 记录打开开关前的 tablet 分布 ---"
B1_BEFORE=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -A5 "HeartbeatPort: 9050" | grep "TabletNum" | awk '{print $2}')
B2_BEFORE=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -A5 "HeartbeatPort: 19050" | grep "TabletNum" | awk '{print $2}')
echo "BE1(9050)  TabletNum = $B1_BEFORE"
echo "BE2(19050) TabletNum = $B2_BEFORE"

echo ""
echo "========== 步骤 4.2：打开均衡开关 =========="
$FE -e "ADMIN SET FRONTEND CONFIG ('disable_balance' = 'false');" 2>&1 \
  | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE 'disable_balance';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "========== 步骤 4.3：等 90 秒，观察数据是否开始搬 =========="
echo "（正在等待 90 秒，让调度器工作）"
sleep 90
B1_AFTER=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -A5 "HeartbeatPort: 9050" | grep "TabletNum" | awk '{print $2}')
B2_AFTER=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -A5 "HeartbeatPort: 19050" | grep "TabletNum" | awk '{print $2}')
echo "BE1(9050)  TabletNum = $B1_BEFORE → $B1_AFTER"
echo "BE2(19050) TabletNum = $B2_BEFORE → $B2_AFTER"
MOVED=$((B2_AFTER - B2_BEFORE))
echo "→ 这 90 秒里，新节点净增 $MOVED 个 tablet"
echo ""
echo "👆 课 9 首次跑（从 8 个 tablet 起步）实测：8→10，90 秒搬了 2 个。"
echo "   搬得少是正常的 —— balance_slot_num_per_path = 1 限定了每块盘同时只搬 1 个。"
echo "   如果这里的数字是 0 或 1，别怀疑没生效，去看步骤 4.4 的 history_tablets。"

echo ""
echo "========== 步骤 4.4：看调度器的工作记录 =========="
$FE -e "SHOW PROC '/cluster_balance';" 2>&1 | grep -vE "^Warning|Using a password"
echo "👆 重点看 history_tablets（累计调度过的 tablet 数）"

echo ""
echo "========== 步骤 4.5：缩容 —— DECOMMISSION（安全做法）=========="
echo "执行：ALTER SYSTEM DECOMMISSION BACKEND '$BE2_HOST:$BE2_HB';"
$FE -e "ALTER SYSTEM DECOMMISSION BACKEND '$BE2_HOST:$BE2_HB';" 2>&1 \
  | grep -vE "^Warning|Using a password"
sleep 5
echo "--- 立刻看状态：SystemDecommissioned 应变为 true ---"
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "HeartbeatPort|Alive|TabletNum|SystemDecommissioned"

echo ""
echo "========== 步骤 4.6：等 120 秒，看数据是否真的迁走 =========="
echo "（正在等待 120 秒）"
sleep 120
D1=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -A5 "HeartbeatPort: 9050" | grep "TabletNum" | awk '{print $2}')
D2=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -A5 "HeartbeatPort: 19050" | grep "TabletNum" | awk '{print $2}')
echo "被摘除的 BE2(19050)：$B2_AFTER → $D2"
echo "留下的     BE1(9050)：$B1_AFTER → $D1"
echo "→ 这 120 秒里，BE2 净减少 $((B2_AFTER - D2)) 个 tablet"
echo ""
echo "👆 课 9 首次跑实测：15→13，另一台 3855→3857。"
echo "   关键判断标准不是绝对值，而是：**被摘除节点的 tablet 数在下降，另一台在上升**"
echo "   —— 这证明数据是真的在往回搬，不是直接丢弃。"

echo ""
echo "========== 步骤 4.7：反悔 —— CANCEL DECOMMISSION =========="
echo "这是 DECOMMISSION 相比 DROP 最大的优势：可撤销"
$FE -e "CANCEL DECOMMISSION BACKEND '$BE2_HOST:$BE2_HB';" 2>&1 \
  | grep -vE "^Warning|Using a password"
sleep 5
echo "--- SystemDecommissioned 应立刻变回 false ---"
$FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "HeartbeatPort|Alive|SystemDecommissioned"

echo ""
echo "========== 步骤 4.8：危险操作 —— 观察 Doris 的防呆设计 =========="
echo "下面这条命令预期会失败，这是故意展示的"
$FE -e "ALTER SYSTEM DROP BACKEND '$BE2_HOST:$BE2_HB';" 2>&1 \
  | grep -vE "^Warning|Using a password"
echo ""
echo "👆 预期报错：It is highly NOT RECOMMENDED to use DROP BACKEND stmt..."
echo "            If you insist, use DROPP instead of DROP"
echo "   注意 DROPP 是两个 P —— 必须故意拼错才能强制执行，手滑删不掉"
echo ""
echo "⚠️ 到此为止，不要真的执行 DROPP。看到这条报错就够了。"

echo ""
echo "========== 步骤 4.9：限速参数（解释为什么业务无感）=========="
$FE -e "SHOW FRONTEND CONFIG LIKE 'balance_slot_num_per_path';" 2>&1 \
  | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE 'partition_rebalance_max_moves_num_per_selection';" 2>&1 \
  | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTEND CONFIG LIKE 'tablet_repair_delay_factor_second';" 2>&1 \
  | grep -vE "^Warning|Using a password"
echo "👆 balance_slot_num_per_path = 1：每块盘同时只搬 1 个 tablet"
echo "   这是"在线业务无感"的原因，代价是慢"

echo ""
echo "========== 步骤 4.10：验证在线查询是否受影响 =========="
echo "连续查 orders 5 次（模拟在线业务）"
for i in 1 2 3 4 5; do
  START=$(date +%s%N)
  runq "SELECT province, SUM(amount) FROM orders GROUP BY province ORDER BY province LIMIT 3;" > /dev/null 2>&1
  END=$(date +%s%N)
  MS=$(( (END - START) / 1000000 ))
  echo "第 $i 次: ${MS} ms"
done
echo "👆 本机实测参考：140 / 128 / 151 / 145 / 159 ms，与平时同量级，无秒级抖动"
echo "   注意：本机数字仅供参考，你的环境会有差异，看量级不要看绝对值"

echo ""
echo "=========================================="
echo " 步骤 4 完成。下一步："
echo "   bash lesson09-step5.sh   （宕机演练，会真的 kill 一个 BE）"
echo "=========================================="

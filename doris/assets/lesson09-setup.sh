#!/bin/bash
# 课 9 步骤 1-3：建实验表 + 知识点 1（Tablet/副本/成本）+ 知识点 2（FE 角色）
# 用法：bash lesson09-setup.sh
#
# 建的对象：cost1（1副本100万行）、repl3（声明3副本5万行）、ha_demo（声明2副本5万行）
# 清理：bash lesson09-cleanup.sh

MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "=========================================="
echo " 课 9 环境准备：建实验表"
echo "=========================================="

echo ""
echo "========== 步骤 0：先看清集群现状 =========="
echo ""
echo "--- 0.1 有几个 BE ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "BackendId|Host|HeartbeatPort|Alive|TabletNum"

echo ""
echo "--- 0.2 有几个 FE ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "Name|Role|IsMaster|Join|Alive"

echo ""
echo "--- 0.3 关键体检：tablet 数 vs 副本数 ---"
echo "👆 判断标准：ReplicaNum == TabletNum 表示整机零冗余"
echo "           ReplicaNum == TabletNum × 2 表示全部 2 副本"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "SHOW PROC '/statistic';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "========== 步骤 1：建实验表 =========="

echo ""
echo "--- 1.1 cost1：单副本 100 万行（量化存储成本用）---"
runq "DROP TABLE IF EXISTS cost1;"
runq "CREATE TABLE cost1 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '1');"
echo "表已建，开始插 100 万行..."
runq "INSERT INTO cost1 SELECT user_id % 1000000, province, amount FROM orders LIMIT 1000000;"
echo "cost1 插入完成"

echo ""
echo "--- 1.2 repl3：声明 3 副本，5 万行（观察"请求 vs 实际"）---"
runq "DROP TABLE IF EXISTS repl3;"
runq "CREATE TABLE repl3 (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '3');"
runq "INSERT INTO repl3 SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;"
echo "repl3 插入完成"

echo ""
echo "--- 1.3 ha_demo：声明 2 副本，5 万行 ---"
runq "DROP TABLE IF EXISTS ha_demo;"
runq "CREATE TABLE ha_demo (
  id INT NOT NULL,
  province VARCHAR(16) NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 6
PROPERTIES ('replication_num' = '2');"
runq "INSERT INTO ha_demo SELECT user_id % 1000000, province, amount FROM orders LIMIT 50000;"
echo "ha_demo 插入完成"

echo ""
echo "⚠️ 注意：SHOW DATA 的统计有延迟（课 6 踩过的坑）。"
echo "   如果这里等不够，SHOW DATA 会报出行数只有一部分（本机曾出现 499228/1000000）。"
echo "   下面等 75 秒，并且先查实际行数确认数据已到位"
sleep 75
echo "--- 确认 cost1 实际行数（应 = 1000000）---"
runq "SELECT COUNT(*) AS actual_rows FROM cost1;"
echo "👆 若这里显示 1000000 但 SHOW DATA 仍少，说明统计还没刷完，再等一会儿即可"

echo ""
echo "========== 步骤 2：知识点 1 —— Tablet、副本与成本 =========="

echo ""
echo "--- 2.1 cost1 的物理布局（分区/分桶/副本数）---"
runq "SHOW PARTITIONS FROM cost1;" | head -5

echo ""
echo "--- 2.2 cost1 的 tablet 落在哪些 BE 上 ---"
echo "👆 数一下 BackendId 有几种值 = 副本实际分布在几台机器"
runq "SHOW TABLETS FROM cost1;" | awk 'NR>1{print $3}' | sort | uniq -c

echo ""
echo "--- 2.3 量化存储成本 ---"
runq "SHOW DATA FROM cost1;"
echo "👆 参考值：100 万行 1 副本 ≈ 2.553 MB"
echo "   换算：2 副本 ≈ 5.1 MB，3 副本 ≈ 7.7 MB（存储成本是 × N）"
echo "   ⚠️ 若你看到的数字明显偏小（如 1.260 MB / 499228 行），是统计延迟，不是数据丢了。"
echo "      用 SELECT COUNT(*) 确认实际行数，或再等 30 秒重查 SHOW DATA。"

echo ""
echo "--- 2.4 验证"3 副本请求"实际落地了几份 ---"
echo "👆 数返回行数：若是 6 行（= 分桶数）说明每个 tablet 只有 1 个副本"
runq "SHOW TABLETS FROM repl3;" | awk 'NR>1{print $3}' | sort | uniq -c
echo "总副本数 = "
runq "SHOW TABLETS FROM repl3;" | tail -n +2 | wc -l

echo ""
echo "--- 2.5 尝试补齐副本：观察反亲和规则的拦截 ---"
echo "⚠️ 下面这条命令在"两台 BE 同主机"时一定报错，这是本课的教学重点之一"
runq "ALTER TABLE ha_demo SET ('replication_num' = '2');"
echo "👆 若看到 'or maybe all be on same host' 就是反亲和规则在拦"

echo ""
echo "--- 2.6 每天的体检视图 ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "SHOW PROC '/cluster_health/tablet_health';" 2>&1 \
  | grep -vE "^Warning|Using a password"
echo "👆 判断标准：HealthyNum 应等于 TabletNum，ReplicaMissingNum 应为 0"

echo ""
echo "========== 步骤 3：知识点 2 —— FE 角色与命令 =========="

echo ""
echo "--- 3.1 看 FE 角色 ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "Name|Host|EditLogPort|Role|IsMaster|Join|Alive|ReplayedJournalId"

echo ""
echo "--- 3.2 登记一个新 Follower（端口是 edit_log_port，默认 9010）---"
FE="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"
$FE -e "ALTER SYSTEM ADD FOLLOWER '127.0.0.1:9011';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "--- 3.3 登记一个 Observer ---"
$FE -e "ALTER SYSTEM ADD OBSERVER '127.0.0.1:9012';" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "--- 3.4 再看列表 ---"
echo "👆 预期：3 个 FE 都在，但新加的两个是 Join: false / Alive: false"
echo "   原因：ADD 只是登记，真正加入要靠 FE 进程带 --helper 启动拉元数据"
$FE -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "Name|Role|IsMaster|Join|Alive"

echo ""
echo "--- 3.5 清理，恢复单 FE ---"
$FE -e "ALTER SYSTEM DROP FOLLOWER '127.0.0.1:9011';" 2>&1 | grep -vE "^Warning|Using a password"
$FE -e "ALTER SYSTEM DROP OBSERVER '127.0.0.1:9012';" 2>&1 | grep -vE "^Warning|Using a password"
$FE -e "SHOW FRONTENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "Role|IsMaster|Alive"

echo ""
echo "🟡 边界提醒：本步骤验证的是命令语法与注册流程。"
echo "   选举过程因单机限制未实测 —— ADD 出来的节点没有真实进程，不会真的参与投票。"

echo ""
echo "=========================================="
echo " setup 完成。下一步："
echo "   bash lesson09-step4.sh   （扩缩容与数据均衡，需第二 BE）"
echo "=========================================="

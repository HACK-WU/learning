#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "############ 清理阶段 2 遗留的三张表 ############"
echo "--- 清理前 shop 库表清单 ---"
Q "SHOW TABLES"

echo ""
echo "--- 1. DROP t_part_day（2920 tablet，元数据负担最大）---"
Q "DROP TABLE t_part_day"

echo "--- 2. DROP idx_demo（578MB，含倒排 + NGram 索引）---"
Q "DROP TABLE idx_demo"

echo "--- 3. DROP rollup_v2（建 Rollup 失败残留）---"
Q "DROP TABLE rollup_v2"

echo ""
echo "--- 清理课 6 实验残留表 ---"
for T in gc_on gc_off vt version_demo; do
  echo "  DROP $T"
  Q "DROP TABLE IF EXISTS $T"
done

echo ""
echo "--- 停止 Routine Load 作业（课 6 已完成）---"
Q "STOP ROUTINE LOAD FOR shop.kafka_rl_orders"

echo ""
echo "############ 清理后状态 ############"
Q "SHOW TABLES"
echo ""
echo "--- 剩余 Routine Load 作业（应为空）---"
Q "SHOW ROUTINE LOAD"

echo ""
echo "############ 内存与容器状态 ############"
free -h
echo ""
docker ps --format 'table {{.Names}}|{{.Status}}' | head -10

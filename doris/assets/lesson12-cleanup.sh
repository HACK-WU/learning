#!/bin/bash
# 课 12 收尾：清理实验表与共享存储上的临时数据
# 用法：bash lesson12-cleanup.sh
#
# ⚠️ 只删本课建的表，不动前 11 课的任何既有表

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "===== 1. 清理本课建的实验表 ====="
for t in anti_kv anti_txn anti_txn2 log_search log_cn local_1m local_10k ext_orders_s3 s3_csv_ext; do
  q "DROP TABLE IF EXISTS $t;" >/dev/null 2>&1
  echo "  dropped (if exists): $t"
done

echo ""
echo "===== 2. 清理共享存储上的临时 parquet ====="
docker exec doris-minio sh -c "rm -rf /data/doris-demo/l12/" 2>&1
echo "  已删除 s3://doris-demo/l12/"
docker exec doris-minio sh -c "ls /data/doris-demo/ 2>&1"

echo ""
echo "===== 3. 确认前 11 课的既有表都还在 ====="
q "SHOW TABLES;" | head -60

echo ""
echo "===== 4. 确认全局设置状态 ====="
q "SHOW VARIABLES LIKE 'enable_sql_cache';"
q "SHOW VARIABLES LIKE 'enable_spill';"
q "SHOW VARIABLES LIKE 'enable_profile';"

echo ""
echo "===== 5. 确认集群健康 ====="
q "SHOW PROC '/cluster_health/tablet_health';" | head -5
q "SHOW BACKENDS\G" | grep -E "^ +(Host|Alive):" | head -6

echo ""
echo "===== cleanup 完成 ====="
echo "  本课遗留状态（供 Phase 3 综合实战参考）："
echo "    - enable_sql_cache=false（课 7 关的，测性能用）"
echo "    - 容器 doris-learn / doris-minio / doris-kafka 保留"
echo "    - orders 2150 万行等既有表完好"

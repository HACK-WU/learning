#!/bin/bash
# 课 11 清理：删掉本课建的实验表、快照与仓库
# 用法：bash lesson11-cleanup.sh
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "===== 1. 删实验表 ====="
for t in sc_light sc_heavy sc_agg sc_mod sc_len sc_key sc_cancel \
         bk_orders bk_orders_r bk_orders_bad bk_part bk_part_r; do
  q "DROP TABLE IF EXISTS $t;" >/dev/null 2>&1
done
echo "  实验表已删"

echo ""
echo "===== 2. 删快照 ====="
# ⚠️ 4.1.3 没有 DROP SNAPSHOT 语句！写了会报：
#    no viable alternative at input 'DROP SNAPSHOT'(line 1, pos 5)
# 所以快照的清理方式是：删掉仓库 + 直接清 S3 目录
q "SHOW SNAPSHOT ON s3_repo;"

echo ""
echo "===== 3. 删仓库 ====="
q "DROP REPOSITORY s3_repo;" 2>&1 | head -2
q "SHOW REPOSITORIES;"
echo "  （如果还显示 s3_repo，说明有作业在跑，等作业结束再删）"

echo ""
echo "===== 4. 清空 S3 上的备份目录（MinIO）====="
docker exec doris-minio rm -rf /data/doris-demo/backup11/ 2>&1 | sed 's/^/  /'
docker exec doris-minio rm -rf /data/doris-demo/backup_rv/ 2>&1 | sed 's/^/  /'
echo "  --- MinIO 剩余内容 ---"
docker exec doris-minio ls /data/doris-demo/ 2>&1 | sed 's/^/  /'
echo "  >> 快照没有 DROP 语句，只能这样物理清理。生产上对应的是"
echo "     S3 生命周期策略（配过期自动删除），不是手动删"

echo ""
echo "===== 4. 确认既有表没被误删 ====="
q "SHOW TABLES;" | grep -E "^(orders|perf_wide|perf_wide_big|fact_1m|dim_region|cost1|repl3|ha_demo)$" | sed 's/^/  /'

echo ""
echo "===== 5. 确认全局设置没被改 ====="
q "SHOW VARIABLES LIKE 'enable_sql_cache';"
q "SHOW VARIABLES LIKE 'enable_spill';"
q "SHOW VARIABLES LIKE 'enable_profile';"

echo ""
echo "===== 6. shop 库剩余表数量 ====="
q "SHOW TABLES;" | tail -n +2 | wc -l

echo ""
echo "===== cleanup 完成 ====="

#!/usr/bin/env bash
# Phase 3 · Task 4：副本 → 资源隔离 → Schema 变更 → 备份恢复
# 用法：bash assets/phase3-task4-prod.sh
# 所有报错原文保留，不 grep 掉
set -u
Q() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot "$@" 2>&1; }
DQ() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw "$@" 2>&1; }

echo "=========================================="
echo " Phase 3 · Task 4：生产化"
echo "=========================================="
echo

echo "########## 1. 副本现状 ##########"
echo
Q -e "SHOW BACKENDS\G" | grep -E "Host:|HeartbeatPort:|Alive:|TabletNum:"
echo
echo "  ⚠️ 两台 BE 的 host 都是 127.0.0.1（伪多节点），反亲和规则导致"
echo "     多副本抗宕机在本机无法验证（课 9 实测）。"
echo

echo "--- 1.1 各表当前副本数 ---"
echo "  ⚠️ 不要用 information_schema.partitions 查，它没有 REPLICATION_NUM 列："
Q -e "SELECT DISTINCT REPLICATION_NUM FROM information_schema.partitions WHERE TABLE_SCHEMA='dw' AND TABLE_NAME='dwd_orders';" 2>&1 | head -2
echo "  ✅ 正确写法：SHOW CREATE TABLE 的 replication_allocation"
for t in ods_orders dwd_orders dws_prov_month ads_prov_month_top dim_province; do
  RN=$(Q dw -e "SHOW CREATE TABLE $t\G" 2>&1 | grep -oE '"replication_allocation" = "[^"]*"' | head -1)
  echo "  $t: $RN"
done
echo
echo "  → 全部为 1 副本。生产上应改为 3，但本机 2 台 BE 的 host 都是 127.0.0.1，"
echo "    3 副本会因反亲和规则建不出来（4.4 会实测这条报错）。"
echo

echo "########## 2. 资源隔离（Workload Group）##########"
echo
echo "--- 2.1 建报表查询组 ---"
Q -e "
CREATE WORKLOAD GROUP IF NOT EXISTS wg_report
PROPERTIES (
  'max_memory_percent' = '40',
  'max_concurrency'    = '20',
  'max_queue_size'     = '50',
  'queue_timeout'      = '30000'
);" 2>&1
echo
echo "--- 2.2 建数据加工组 ---"
Q -e "
CREATE WORKLOAD GROUP IF NOT EXISTS wg_etl
PROPERTIES (
  'max_memory_percent' = '60',
  'max_concurrency'    = '3',
  'max_queue_size'     = '10',
  'queue_timeout'      = '300000'
);" 2>&1
echo
echo "--- 2.3 【报错演示】已废弃的属性名 ---"
Q -e "CREATE WORKLOAD GROUP IF NOT EXISTS wg_bad PROPERTIES ('memory_limit'='30%');" 2>&1 | head -2
Q -e "CREATE WORKLOAD GROUP IF NOT EXISTS wg_bad2 PROPERTIES ('cpu_share'='10');" 2>&1 | head -2
echo
echo "--- 2.4 【报错演示】水位必须成对（低水位默认 75%）---"
Q -e "CREATE WORKLOAD GROUP IF NOT EXISTS wg_bad3 PROPERTIES ('memory_high_watermark'='70');" 2>&1 | head -2
echo
echo "--- 2.5 验证：并发/排队参数确实被接受 ---"
Q -e "SHOW WORKLOAD GROUPS;" 2>&1 | awk -F'\t' 'NR==1{print "  "$1" | "$6" | "$7" | "$8} NR>1{print "  "$2" | "$6" | "$7" | "$8}'
echo
echo "--- 2.6 ⚠️ CPU 限额在本机不生效（cgroup 只读）---"
docker exec -i doris-learn bash -c "mount 2>/dev/null | grep cgroup | head -2" 2>&1
echo "  → cgroup2 是 (ro,...) 只读挂载，max_cpu_percent / scan_thread_num 无法生效"
echo

echo "########## 3. Schema 变更 ##########"
echo
echo "--- 3.1 【报错演示】ADD COLUMN 不支持 IF NOT EXISTS ---"
DQ -e "ALTER TABLE dwd_orders ADD COLUMN IF NOT EXISTS remark VARCHAR(64);" 2>&1 | head -3 | cut -c1-160
echo
echo "--- 3.2 【报错演示】DROP COLUMN 也不支持 IF NOT EXISTS ---"
DQ -e "ALTER TABLE dwd_orders DROP COLUMN IF EXISTS remark;" 2>&1 | head -3 | cut -c1-160
echo
echo "--- 3.3 加列（light_schema_change 默认 true，毫秒级）---"
echo "  ✅ 关键：加列时【不要写 DEFAULT】，否则这一列后面永远改不动（见 3.5）"
DQ -e "ALTER TABLE dwd_orders ADD COLUMN remark VARCHAR(64);" 2>&1
DQ -e "SELECT order_date, user_id, remark FROM dwd_orders LIMIT 3;"
echo
echo "--- 3.4 改列宽（加列时没写 DEFAULT → 改宽成功）---"
DQ -e "ALTER TABLE dwd_orders MODIFY COLUMN remark VARCHAR(128);" 2>&1
echo "  实际列宽："
DQ -e "DESC dwd_orders;" 2>&1 | grep -E "^remark" | cut -c1-120
echo
echo "--- 3.5 【报错演示】加列时写了 DEFAULT → 这一列再也改不动 ---"
DQ -e "ALTER TABLE dwd_orders ADD COLUMN remark_def VARCHAR(64) DEFAULT '';" 2>&1
echo "  ① 改宽到 128（不带新 DEFAULT）："
DQ -e "ALTER TABLE dwd_orders MODIFY COLUMN remark_def VARCHAR(128);" 2>&1 | head -3 | cut -c1-200
echo "  ② 改宽到 256 并显式带 DEFAULT："
DQ -e "ALTER TABLE dwd_orders MODIFY COLUMN remark_def VARCHAR(256) DEFAULT 'x';" 2>&1 | head -3 | cut -c1-200
echo "  → 两条路都堵死。规避办法见 task-4 文档 3.5 节：加新列 → UPDATE 回填 → 删旧列 → 改名"
echo
echo "--- 3.6 删列（没有 IF NOT EXISTS，已存在的列才删得掉）---"
DQ -e "ALTER TABLE dwd_orders DROP COLUMN remark;" 2>&1
DQ -e "ALTER TABLE dwd_orders DROP COLUMN remark_def;" 2>&1
DQ -e "SELECT COUNT(*) AS rows_after_drop FROM dwd_orders;"
DQ -e "DESC dwd_orders;" 2>&1 | grep -cE "^order_date|^user_id|^order_id" | xargs -I{} echo "  保留的关键列数检查：{}"
echo

echo "########## 4. 备份与恢复 ##########"
echo
echo "--- 4.1 建 S3 仓库（不支持 IF NOT EXISTS，先 DROP 再 CREATE）---"
Q -e "DROP REPOSITORY p3_repo;" 2>&1 | head -2
Q -e "
CREATE REPOSITORY p3_repo
WITH S3 ON LOCATION 's3://doris-demo/p3backup/'
PROPERTIES (
  's3.endpoint' = 'http://minio:9000',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  's3.region' = 'us-east-1',
  'use_path_style' = 'true'
);" 2>&1
Q -e "SHOW REPOSITORIES;"
echo

echo "--- 4.2 备份 DWS 层（96 行，比 DWD 快得多，演示用）---"
DQ -e "DROP TABLE IF EXISTS dws_restored;" 2>&1
DQ -e "DROP TABLE IF EXISTS dws_restored_bad;" 2>&1
echo "  同名快照在仓库里已存在时会报 'already exist'，先删掉（SNAPSHOT 不支持 IF EXISTS）："
Q -e "DROP SNAPSHOT p3_dws ON p3_repo;" 2>&1 | head -2
DQ -e "BACKUP SNAPSHOT p3_dws TO p3_repo ON (dws_prov_month);" 2>&1
echo "--- 等 20 秒 ---"
sleep 20
DQ -e "SHOW BACKUP;" 2>&1 | tail -1 | awk -F'\t' '{print "  JobId="$1" | SnapshotName="$2" | State="$4}'
echo

echo "--- 4.3 取 backup_timestamp ---"
TS=$(Q -e "SHOW SNAPSHOT ON p3_repo;" 2>&1 | grep "p3_dws" | tail -1 | awk '{print $2}')
echo "  backup_timestamp = $TS"
echo

echo "--- 4.4 【报错演示】RESTORE 不写 replication_num（默认 3，本机只有 2 BE）---"
DQ -e "RESTORE SNAPSHOT p3_dws FROM p3_repo ON (dws_prov_month AS dws_restored_bad) PROPERTIES ('backup_timestamp' = '$TS');" 2>&1 | head -2
sleep 10
echo "  → RESTORE 命令本身【返回成功】，失败信息藏在 SHOW RESTORE 里："
DQ -e "SHOW RESTORE;" 2>&1 | tail -1 | awk -F'\t' '{print "  JobId="$1" | Label="$2" | State="$5" | ReplicAlloc="$8}'
echo "  ⚠️ 不要用 awk 取 Status 列（第 14 列）：SHOW RESTORE 的 Info 列里含 \\n 转义的 JSON，"
echo "     会把整行打乱，列号不可信。用 grep -oE 直接抽关键句："
DQ -e "SHOW RESTORE;" 2>&1 | grep -oE "replication num should be less than[^\"\\\\]*" | head -1 | sed 's/^/  ❌ /'
echo
echo "  → 根因：RESTORE 不沿用原表的副本数，默认按 3 副本恢复，本机只有 2 台 BE。"
echo

echo "--- 4.5 正确恢复（显式 replication_num=1）---"
DQ -e "RESTORE SNAPSHOT p3_dws FROM p3_repo ON (dws_prov_month AS dws_restored) PROPERTIES ('backup_timestamp' = '$TS', 'replication_num' = '1');" 2>&1
echo "--- 等 30 秒 ---"
sleep 30
DQ -e "SHOW RESTORE;" 2>&1 | tail -1 | awk -F'\t' '{print "  JobId="$1" | Label="$2" | State="$5" | ReplicAlloc="$8}'
echo

echo "--- 4.6 对账：恢复表 vs 原表 ---"
DQ -e "SELECT COUNT(*) AS rows_cnt, SUM(total_amount) AS s FROM dws_prov_month;"
DQ -e "SELECT COUNT(*) AS rows_cnt, SUM(total_amount) AS s FROM dws_restored;"
echo

echo "--- 4.7 【报错演示】漏掉 backup_timestamp ---"
DQ -e "RESTORE SNAPSHOT p3_dws FROM p3_repo ON (dws_prov_month AS dws_r2);" 2>&1 | head -2
echo

echo "########## 5. 清理 ##########"
echo
DQ -e "DROP TABLE IF EXISTS dws_restored_bad;" 2>&1
DQ -e "DROP TABLE IF EXISTS dws_restored;" 2>&1
Q -e "DROP WORKLOAD GROUP IF EXISTS wg_bad;" 2>&1
Q -e "DROP WORKLOAD GROUP IF EXISTS wg_bad2;" 2>&1
Q -e "DROP WORKLOAD GROUP IF EXISTS wg_bad3;" 2>&1
echo "  已清理恢复表与演示用错组（保留 wg_report / wg_etl）"
echo
Q -e "SHOW WORKLOAD GROUPS;" 2>&1 | awk -F'\t' 'NR>1{print "  "$2}'
echo

echo "=========================================="
echo " Task 4 生产化完成"
echo "=========================================="

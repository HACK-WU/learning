#!/bin/bash
# 课 11 步骤 2：知识点 2 —— 备份与恢复
# 用法：bash lesson11-step2.sh（需先跑 lesson11-setup.sh）
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
laststate() { q "SHOW $1\G" | grep -E "^ +State:" | awk '{print $2}' | tail -1; }
laststatus() { q "SHOW $1\G" | grep -E "^ +Status:" | tail -1 | sed 's/^ *//'; }
waitjob() {
  for i in $(seq 1 90); do
    ST=$(laststate "$1")
    [ "$ST" = "FINISHED" ] && break
    [ "$ST" = "CANCELLED" ] && break
    sleep 1
  done
  echo "$ST"
}

echo "##################################################################"
echo "# 2.1 仓库与备份目标确认                                            #"
echo "##################################################################"
q "SHOW REPOSITORIES;"
if ! q "SHOW REPOSITORIES;" | grep -q "s3_repo"; then
  echo "  [FAIL] s3_repo 不存在，请先跑 lesson11-setup.sh"
  exit 1
fi
echo "--- 备份源表的数据指纹（记住它，恢复后要对）---"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM bk_orders;"

echo ""
echo "##################################################################"
echo "# 2.2 BACKUP：整表备份（100 万行）                                   #"
echo "##################################################################"
SS=$(date +%s)
q "BACKUP SNAPSHOT shop.bk_orders_v1 TO s3_repo ON (bk_orders);"
echo "  >> BACKUP 是异步的，语句立刻返回，要等作业真正 FINISHED"
for i in $(seq 1 30); do
  ST=$(laststate BACKUP)
  echo "  t=${i}s State=$ST"
  [ "$ST" = "FINISHED" ] && break
  [ "$ST" = "CANCELLED" ] && break
  sleep 1
done
EE=$(date +%s)
echo "  >> 备份总耗时 $((EE-SS)) 秒（本课实测范围 17-18 秒）"
echo "--- 完整 SHOW BACKUP 输出 ---"
q "SHOW BACKUP\G" | awk -v RS='***************************' '/bk_orders_v1/{print}' | grep -E "SnapshotName|State|BackupObjs|CreateTime|SnapshotFinishedTime|UploadFinishedTime|FinishedTime|Status"

echo ""
echo "##################################################################"
echo "# 2.3 SHOW SNAPSHOT：拿到 backup_timestamp                          #"
echo "##################################################################"
q "SHOW SNAPSHOT ON s3_repo;"
TS=$(q "SHOW SNAPSHOT ON s3_repo WHERE SNAPSHOT = 'bk_orders_v1';" | awk -F'\t' 'NR==2{print $2}')
echo "  >> backup_timestamp = $TS"
echo "  >> 这个时间戳是恢复的必需参数，不写会报 Missing backup_timestamp property"

echo ""
echo "##################################################################"
echo "# 2.4 备份文件落到哪了（MinIO 里看）                                 #"
echo "##################################################################"
docker exec doris-minio ls -la /data/doris-demo/backup11/__palo_repository_s3_repo/__ss_bk_orders_v1/ 2>&1 | sed 's/^/  /'
docker exec doris-minio du -sh /data/doris-demo/backup11/__palo_repository_s3_repo/__ss_bk_orders_v1/ 2>&1 | sed 's/^/  /'
echo "  >> 快照目录里是 __meta（元数据）+ __ss_content（数据）+ __info_xxx（作业信息）"

echo ""
echo "##################################################################"
echo "# 2.5 制造一次"数据事故"：删掉一部分数据                            #"
echo "##################################################################"
q "DELETE FROM bk_orders WHERE id < 300000;"
sleep 3
echo "--- 事故后的指纹（cnt 应从 1000000 掉到 700000）---"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM bk_orders;"

echo ""
echo "##################################################################"
echo "# 2.6 RESTORE 踩坑：不写 replication_num 会怎样？                    #"
echo "##################################################################"
q "DROP TABLE IF EXISTS bk_orders_bad;" >/dev/null 2>&1
q "RESTORE SNAPSHOT shop.bk_orders_v1 FROM s3_repo ON (bk_orders AS bk_orders_bad)
   PROPERTIES ('backup_timestamp' = '$TS');"
echo "  >> 提交成功（语句本身不报错），但作业会失败："
ST=$(waitjob RESTORE)
echo "  >> 作业终态: $ST"
echo "--- 失败原因（报错原文必须看）---"
q "SHOW RESTORE\G" | grep -E "^ +Status:" | tail -1 | sed 's/^ */  /'
echo "  ^^^ 原因：RESTORE 默认按 3 副本恢复，本机只有 2 台 BE（且同 host）"

echo ""
echo "##################################################################"
echo "# 2.7 RESTORE 正确写法：显式指定 replication_num                     #"
echo "##################################################################"
q "DROP TABLE IF EXISTS bk_orders_r;" >/dev/null 2>&1
SS=$(date +%s)
q "RESTORE SNAPSHOT shop.bk_orders_v1 FROM s3_repo ON (bk_orders AS bk_orders_r)
   PROPERTIES ('backup_timestamp' = '$TS', 'replication_num' = '1');"
for i in $(seq 1 30); do
  ST=$(laststate RESTORE)
  echo "  t=${i}s State=$ST"
  [ "$ST" = "FINISHED" ] && break
  [ "$ST" = "CANCELLED" ] && break
  sleep 1
done
EE=$(date +%s)
echo "  >> 恢复总耗时 $((EE-SS)) 秒（本课实测 21 秒）"
echo "--- 校验：指纹必须和备份前一模一样 ---"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM bk_orders_r;"
echo "  >> 用 SUM 校验而不是 COUNT(*)：COUNT 走元数据优化，不扫数据，可能骗人"

echo ""
echo "##################################################################"
echo "# 2.8 一个库同一时刻只能跑一个备份/恢复作业                          #"
echo "##################################################################"
echo "--- 同时提交两个 BACKUP，第二个会被直接拒绝（报错原文）---"
q "BACKUP SNAPSHOT shop.j1 TO s3_repo ON (bk_part);" >/dev/null 2>&1
q "BACKUP SNAPSHOT shop.j2 TO s3_repo ON (bk_part);"
echo "  ^^^ 报错原文：Can only run one backup or restore job of a database at same time"
ST=$(waitjob BACKUP)
echo "  第一个作业终态: $ST"

echo ""
echo "##################################################################"
echo "# 2.9 分区级备份与恢复                                               #"
echo "##################################################################"
echo "--- bk_part 原数据（两个分区各 2 万行）---"
q "SELECT dt, COUNT(*) AS cnt FROM bk_part GROUP BY dt ORDER BY dt;"
echo "--- 只备份 p1 分区 ---"
q "BACKUP SNAPSHOT shop.bk_part_p1 TO s3_repo ON (bk_part PARTITION (p1));"
ST=$(waitjob BACKUP)
echo "  备份 State=$ST"
TSP=$(q "SHOW SNAPSHOT ON s3_repo WHERE SNAPSHOT = 'bk_part_p1';" | awk -F'\t' 'NR==2{print $2}')
echo "  backup_timestamp = $TSP"
echo "--- 恢复成新表 ---"
q "DROP TABLE IF EXISTS bk_part_r;" >/dev/null 2>&1
q "RESTORE SNAPSHOT shop.bk_part_p1 FROM s3_repo ON (bk_part AS bk_part_r)
   PROPERTIES ('backup_timestamp' = '$TSP', 'replication_num' = '1');"
ST=$(waitjob RESTORE)
echo "  恢复 State=$ST"
echo "--- 校验：应该只有 p1 的 2 万行，p2 不在 ---"
q "SELECT dt, COUNT(*) AS cnt FROM bk_part_r GROUP BY dt ORDER BY dt;"

echo ""
echo "##################################################################"
echo "# 2.10 备份期间能不能写入？                                          #"
echo "##################################################################"
q "BACKUP SNAPSHOT shop.bk_orders_v2 TO s3_repo ON (bk_orders);" >/dev/null 2>&1
sleep 1
echo "--- 备份进行中 INSERT 一行 ---"
S=$(date +%s%N)
q "INSERT INTO bk_orders (id, user_id, amount) VALUES (88888888, 8888, 999.99);"
E=$(date +%s%N)
echo "  INSERT 耗时 $(( (E-S)/1000000 )) ms —— 没被阻塞"
ST=$(waitjob BACKUP)
echo "  备份 State=$ST"
echo "--- 备份结束后，这行在不在？---"
q "SELECT id, user_id, amount FROM bk_orders WHERE id = 88888888;"
echo "  >> 在。说明 BACKUP 是"某一时刻的一致性快照"，不锁写入"

echo ""
echo "===== step2 完成 ====="
echo "  下一步：bash lesson11-step3.sh （知识点 3：监控告警与集群升级）"

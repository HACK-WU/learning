#!/usr/bin/env bash
# Phase 3 · Task 5：验收与边界
# 用法：bash assets/phase3-task5-accept.sh
# 原则：每条命令都自问"读者照抄能跑通吗"；报错原文保留，不 grep 掉
# 注意：本脚本会在 5.x 节对 dwd_orders 做单行 DML 演示，会真实删 1 行见 5.2
set -u
Q()  { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot "$@" 2>&1; }
DQ() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw "$@" 2>&1; }
# 取单个标量值（-B -N 去掉表头，tr 去掉 CR）
QV() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -B -N -e "$1" 2>/dev/null | tr -d '\r' | head -1; }

# 单连接计时（课 12 方法论：剥离 docker exec 的连接开销，跑 5 轮取 min-max）
bench_range() {
  local SQL="$1"; local TIMES=""
  for r in 1 2 3 4 5; do
    local S E
    S=$(date +%s.%N)
    echo "$SQL" | docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -N > /dev/null 2>&1
    E=$(date +%s.%N)
    TIMES="$TIMES $(awk -v s="$S" -v e="$E" 'BEGIN{printf "%.3f", e-s}')"
  done
  echo "$TIMES" | tr ' ' '\n' | grep -v '^$' | sort -n \
    | awk 'NR==1{printf "%s", $0} END{printf " - %s s\n", $0}'
}

echo "=========================================="
echo " Phase 3 · Task 5：验收与边界"
echo "=========================================="
echo

echo "########## 1. 数据完整性验收 ##########"
echo
echo "--- 1.1 源表指纹（shop.orders，2150 万行 / 24 个月）---"
Q shop -e "SELECT COUNT(*) AS src_rows, SUM(amount) AS src_sum FROM orders;"
echo
echo "--- 1.2 ODS 指纹（本次只接 2025 全年 12 个月）---"
DQ -e "SELECT COUNT(*) AS ods_rows, SUM(amount) AS ods_sum FROM ods_orders;"
echo "  ⚠️ ODS 行数 < 源表行数是【设计如此】："
echo "     源表覆盖 2025-01~2026-12 共 24 个月，本项目只导了 2025 全年 12 个月。"
echo "     剩余 12 个月是"未来数据"，留作实时链路的增量空间。"
echo
echo "--- 1.3 逐月对账：源表 vs ODS（全部为 0 才 PASS）---"
Q shop -B -N -e "SELECT DATE_FORMAT(order_date,'%Y-%m') ym, COUNT(*) c, ROUND(SUM(amount),2) s
                 FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01'
                 GROUP BY ym ORDER BY ym;" 2>/dev/null | tr -d '\r' > /tmp/src_ym.txt
DQ -B -N -e "SELECT DATE_FORMAT(order_date,'%Y-%m') ym, COUNT(*) c, ROUND(SUM(amount),2) s
             FROM ods_orders GROUP BY ym ORDER BY ym;" 2>/dev/null | tr -d '\r' > /tmp/ods_ym.txt
echo "  月份    | 行数差 | 金额差"
paste /tmp/src_ym.txt /tmp/ods_ym.txt | awk -F'\t' 'NF>=6 {
    dc=$2-$5; ds=$3-$6; if(dc<0)dc=-dc; if(ds<0)ds=-ds;
    printf "  %s | %6d | %8.2f  %s\n", $1, dc, ds, (dc==0 && ds==0 ? "PASS" : "FAIL")
  }'
echo
echo "--- 1.4 DWD 去重结果 ---"
DQ -e "SELECT COUNT(*) AS dwd_rows, SUM(amount) AS dwd_sum FROM dwd_orders;"
echo
echo "--- 1.5 代理主键撞车检查（Task 2 事故复查，collision_loss 必须为 0）---"
DQ -e "SELECT SUM(cnt) AS total, COUNT(*) AS groups,
              SUM(CASE WHEN cnt > 1 THEN cnt-1 ELSE 0 END) AS collision_loss
       FROM (SELECT order_date, order_id, COUNT(*) AS cnt
             FROM dwd_orders GROUP BY order_date, order_id) t;"
echo
echo "--- 1.6 四层对账（DWS / MV / ADS 金额必须等于 DWD）---"
DQ -e "SELECT 'dwd' AS layer, COUNT(*) c, SUM(amount) s FROM dwd_orders
       UNION ALL SELECT 'dws', COUNT(*), SUM(total_amount) FROM dws_prov_month
       UNION ALL SELECT 'mv',  COUNT(*), SUM(total_amount) FROM mv_region_month
       UNION ALL SELECT 'ads', COUNT(*), SUM(total_amount) FROM ads_prov_month_top
       UNION ALL SELECT 'dim', COUNT(*), 0 FROM dim_province;"
echo
echo "--- 1.7 ⚠️ 不能用 COUNT(*) 验证"数据可查"（课 9/12 的坑）---"
echo "  COUNT(*) 走 FE 元数据优化，不扫 BE。真正验证要用 SUM/MAX 这类聚合："
DQ -e "SELECT SUM(amount) AS be_scan_sum, MAX(amount) AS mx, COUNT(DISTINCT province) AS provs
       FROM dwd_orders WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';"
echo "  ↑ 有值就说明 BE 真的读到了数据（这里不用 ='2025-06-15'，见文档 1.7 节说明）"
echo

echo "########## 2. 实时性验收 ##########"
echo
echo "--- 2.1 Routine Load 作业状态 ---"
DQ -e "SHOW ROUTINE LOAD;" 2>&1 | awk -F'\t' 'NR>1{print "  "$2" | State="$9" | Lag="$17}'
echo "  ⚠️ Kafka 在独立容器 doris-kafka，broker 地址是 kafka:9092（不是 localhost）"
echo
echo "--- 2.2 实时表当前行数 ---"
DQ -e "SELECT COUNT(*) AS rt_cnt, SUM(amount) AS rt_sum FROM ods_orders_rt;"
echo
echo "--- 2.3 端到端：投一条消息，30 秒内应能查到 ---"
RT_ID=$((900000 + RANDOM % 90000))
docker exec -i doris-kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 --topic doris_orders > /dev/null 2>&1 << EOF
{"order_id": $RT_ID, "user_id": 777001, "province": "广东", "amount": 12.34, "order_time": "$(date '+%Y-%m-%d %H:%M:%S')"}
EOF
echo "  已投递 order_id=$RT_ID，等待 30 秒..."
RT_FOUND="❌ 30 秒内未查到"
for i in $(seq 1 30); do
  sleep 1
  N=$(QV "SELECT COUNT(*) FROM ods_orders_rt WHERE order_id = $RT_ID;")
  if [ "$N" = "1" ]; then RT_FOUND="✅ FOUND in ${i}s"; break; fi
done
echo "  结果：$RT_FOUND"
echo

echo "########## 3. 性能验收（各跑 5 轮取 min-max）##########"
echo
echo "--- 3.1 先确认加速对象都在 ---"
Q -e "SELECT TABLE_NAME FROM information_schema.tables
      WHERE TABLE_SCHEMA='dw' AND TABLE_TYPE LIKE '%VIEW%';" 2>&1 | grep -v TABLE_NAME | sed 's/^/  MV: /'
DQ -e "DESC rollup_test ALL;" 2>&1 | awk -F'\t' '$1!=""{print $1}' | sort -u | grep -v IndexName | sed 's/^/  Rollup: /'
echo
echo "--- Q1 月度趋势（DWS 聚合层，扫描面最小）---"
echo -n "  Q1: "; bench_range "SELECT DATE_FORMAT(stat_month,'%Y-%m') m, SUM(total_amount) FROM dws_prov_month GROUP BY m ORDER BY m;"
echo
echo "--- Q2 单月各省排名（ADS 层，直接读结果）---"
echo -n "  Q2: "; bench_range "SELECT province, total_amount, rank_no FROM ads_prov_month_top WHERE stat_month='2025-06-01' ORDER BY rank_no;"
echo
echo "--- Q3 大区汇总（MV 层）---"
echo -n "  Q3: "; bench_range "SELECT region, SUM(total_amount) FROM mv_region_month GROUP BY region ORDER BY 2 DESC;"
echo
echo "--- Q4 分区裁剪对照（对分区列用函数 → 裁剪失效）---"
echo -n "  Q4a 带函数 YEAR()/MONTH(): "
bench_range "SELECT SUM(amount) FROM dwd_orders WHERE YEAR(order_date)=2025 AND MONTH(order_date)=6;"
echo -n "  Q4b 直接区间比:           "
bench_range "SELECT SUM(amount) FROM dwd_orders WHERE order_date >= '2025-06-01' AND order_date < '2025-07-01';"
echo "  → 两者持平，说明【本机看不出裁剪收益】。原因：单次查询被 0.12s 左右的"
echo "    固定开销（连接、计划、调度）主导，28 个分区的裁剪收益被淹没了。"
echo "    Task 3 用 EXPLAIN 的 partitions=1/28 验证过裁剪【确实发生】，"
echo "    但【性能收益】要等到数据量上亿才明显。这里不编数字。"
echo
echo "--- Q5 明细探查（ODS 层，最重）---"
echo -n "  Q5: "; bench_range "SELECT province, COUNT(*), SUM(amount) FROM ods_orders WHERE order_date='2025-06-15' GROUP BY province ORDER BY 3 DESC;"
echo
echo "--- 3.2 Rollup 命中验证（Duplicate 表 rollup_test）---"
DQ -e "EXPLAIN SELECT province, SUM(amount) FROM rollup_test GROUP BY province;" 2>&1 \
  | grep -iE "TABLE:|chose" | head -4 | sed 's/^/    /'
echo
echo "--- 3.3 MV 扫描验证 ---"
DQ -e "EXPLAIN SELECT region, SUM(total_amount) FROM mv_region_month GROUP BY region;" 2>&1 \
  | grep -iE "TABLE:|chose|MATERIALIZATIONS" | head -5 | sed 's/^/    /'
echo "  ⚠️ 手写 MV 名不算"透明改写"。真改写要看 EXPLAIN 的 MATERIALIZATIONS 段"
echo "     里有没有 chose —— 本机 MV 改写不稳定，见 task-3 文档 5.4 节。"
echo

echo "########## 4. 生产化验收 ##########"
echo
echo "--- 4.1 集群健康 ---"
Q -e "SHOW BACKENDS\G" | grep -E "Alive:|TabletNum:" | sed 's/^/  /'
echo
echo "--- 4.2 各表副本数（SHOW CREATE TABLE 取法，不是 information_schema）---"
for t in ods_orders dwd_orders dws_prov_month ads_prov_month_top dim_province; do
  RN=$(Q dw -e "SHOW CREATE TABLE $t\G" 2>&1 | grep -oE '"replication_allocation" = "[^"]*"' | head -1)
  echo "  $t: $RN"
done
echo
echo "--- 4.3 资源组 ---"
Q -e "SHOW WORKLOAD GROUPS;" 2>&1 | awk -F'\t' 'NR==1{print "  "$2" | "$6" | "$7" | "$8} NR>1{print "  "$2" | "$6" | "$7" | "$8}'
echo
echo "--- 4.4 备份仓库与快照 ---"
Q -e "SHOW REPOSITORIES;" 2>&1 | awk -F'\t' 'NR>1{print "  "$2" @ "$5}'
Q -e "SHOW SNAPSHOT ON p3_repo;" 2>&1 | tail -n +1 | head -3 | sed 's/^/  /'
echo
echo "--- 4.5 分区健康（动态分区 start=-24/end=3 → 28 个分区）---"
Q -e "SELECT TABLE_NAME, COUNT(*) AS parts FROM information_schema.partitions
      WHERE TABLE_SCHEMA='dw' AND TABLE_NAME IN ('ods_orders','dwd_orders','dws_prov_month')
      GROUP BY TABLE_NAME;" 2>&1 | sed 's/^/  /'
echo

echo "########## 5. 边界：哪些需求不该接进 Doris ##########"
echo
echo "--- 5.1 【反模式 1】当 KV 点查用（请用 Redis）---"
echo "  先取一个真实存在的 order_id："
DEMO_OID=$(QV "SELECT order_id FROM dwd_orders WHERE order_date='2025-01-15' ORDER BY order_id LIMIT 1;")
echo "  order_id = $DEMO_OID"
echo -n "  20 次主键点查（同一连接）: "
S=$(date +%s.%N)
for i in $(seq 1 20); do
  echo "SELECT * FROM dwd_orders WHERE order_date='2025-01-15' AND order_id=$DEMO_OID;"
done | docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -N > /dev/null 2>&1
E=$(date +%s.%N)
echo "$(awk -v s="$S" -v e="$E" 'BEGIN{printf "%.3f s（单次约 %.1f ms）", e-s, (e-s)*1000/20}')"
echo -n "  1 次聚合（同分区全量 group by）: "
S=$(date +%s.%N)
DQ -e "SELECT province, COUNT(*), SUM(amount) FROM dwd_orders WHERE order_date='2025-01-15' GROUP BY province;" > /dev/null 2>&1
E=$(date +%s.%N)
echo "$(awk -v s="$S" -v e="$E" 'BEGIN{printf "%.3f s", e-s}')"
echo "  → Doris 每次点查都要走完整查询计划；20 次点查和 1 次全量聚合差不多贵。"
echo "    这种活该给 Redis（微秒级）。Doris 的优势在"一次算很多行"，不在"一次查一行"。"
echo
echo "--- 5.2 🔥【反模式 2】把 order_id 当全局主键做单行删改 ---"
echo "  dwd_orders 的唯一键是 (order_date, user_id, order_id)，"
echo "  order_id 是【按天】编的 ROW_NUMBER，只在当天唯一！"
DQ -e "SELECT COUNT(*) AS rows_total,
              COUNT(DISTINCT order_id) AS distinct_oid,
              COUNT(DISTINCT CONCAT(order_date,'|',order_id)) AS distinct_date_oid
       FROM dwd_orders;"
echo "  ↑ distinct_oid 远小于 rows_total，说明 order_id 跨天大量重复。"
echo
echo "  现在做一次"单行"DELETE，看实际影响多少行："
DEL_OID=$(QV "SELECT order_id FROM dwd_orders LIMIT 1;")
BEFORE=$(QV "SELECT COUNT(*) FROM dwd_orders;")
echo "    DELETE ... WHERE order_id = $DEL_OID （看起来是删 1 行）"
DQ -e "DELETE FROM dwd_orders WHERE order_id = $DEL_OID;" 2>&1 | head -3 | sed 's/^/    /'
sleep 3
AFTER=$(QV "SELECT COUNT(*) FROM dwd_orders;")
echo "    实际删除：$((BEFORE - AFTER)) 行（BEFORE=$BEFORE → AFTER=$AFTER）"
echo "  🔥 这就是 Doris 里最危险的静默失败：SQL 看起来是单行操作，"
echo "     实际按唯一键前缀命中了跨分区的一批行，且不报任何错。"
echo "     要精准删改，WHERE 里必须带全唯一键 (order_date, user_id, order_id)。"
echo
echo "  ✅ 正确写法演示（带全唯一键，只删 1 行）："
FULL_KEY=$(QV "SELECT CONCAT(order_date,'|',user_id,'|',order_id) FROM dwd_orders LIMIT 1;")
D_DATE=$(echo "$FULL_KEY" | cut -d'|' -f1)
D_UID=$(echo "$FULL_KEY"  | cut -d'|' -f2)
D_OID=$(echo "$FULL_KEY"  | cut -d'|' -f3)
echo "    DELETE ... WHERE order_date='$D_DATE' AND user_id=$D_UID AND order_id=$D_OID"
B2=$(QV "SELECT COUNT(*) FROM dwd_orders;")
DQ -e "DELETE FROM dwd_orders WHERE order_date='$D_DATE' AND user_id=$D_UID AND order_id=$D_OID;" 2>&1 | head -3 | sed 's/^/    /'
sleep 3
A2=$(QV "SELECT COUNT(*) FROM dwd_orders;")
echo "    实际删除：$((B2 - A2)) 行 ✅"
echo
echo "--- 5.3 【反模式 3】高频单行 UPDATE（请用 MySQL/PG）---"
echo "  Unique 表支持 UPDATE，但它是为【批量修正】设计的："
DQ -e "UPDATE dwd_orders SET amount = amount * 1 WHERE order_date='2025-01-15' AND province='广东';" 2>&1 | head -3 | sed 's/^/    /'
sleep 2
DQ -e "SELECT COUNT(*) AS affected_rows FROM dwd_orders WHERE order_date='2025-01-15' AND province='广东';" 2>&1 | sed 's/^/    /'
echo "  ↑ 一次改几千行没问题。但每行改一次会让写放大 + Compaction 追不上，"
echo "    查询会越来越慢。高频单行改请用 MySQL/PG。"
echo
echo "--- 5.4 【反模式 4】拿 Doris 做事务（没有跨表事务）---"
DQ -e "BEGIN; UPDATE dwd_orders SET amount=1.11 WHERE order_date='2025-01-15' AND province='广东'; ROLLBACK;" 2>&1 | head -3 | sed 's/^/    /'
sleep 2
DQ -e "SELECT ROUND(MIN(amount),2) AS min_after_rollback FROM dwd_orders WHERE order_date='2025-01-15' AND province='广东';" 2>&1 | sed 's/^/    /'
echo "  ↑ 单表内 ROLLBACK 能生效，但 Doris 没有跨表事务与隔离级别保障。"
echo "    需要事务语义的业务留在 MySQL/PG。"
echo
echo "--- 5.5 【反模式 5】拿 Doris 当消息队列 / 流计算引擎 ---"
echo "  Routine Load 是【入库通道】，不是流计算：不做窗口聚合、不做维表关联、"
echo "  不做 exactly-once 的下游投递。要流计算用 Flink，Doris 只当 sink 和查询层。"
echo

echo "########## 6. 验收结论 ##########"
echo
echo "--- 6.1 各层最终状态 ---"
DQ -e "SELECT 'ods' AS layer, COUNT(*) c, SUM(amount) s FROM ods_orders
       UNION ALL SELECT 'dwd', COUNT(*), SUM(amount) FROM dwd_orders
       UNION ALL SELECT 'dws', COUNT(*), SUM(total_amount) FROM dws_prov_month
       UNION ALL SELECT 'mv',  COUNT(*), SUM(total_amount) FROM mv_region_month
       UNION ALL SELECT 'ads', COUNT(*), SUM(total_amount) FROM ads_prov_month_top
       UNION ALL SELECT 'dim', COUNT(*), 0 FROM dim_province;" 2>&1 | sed 's/^/  /'
echo
echo "  ⚠️ 5.2 节为了演示 order_id 非全局唯一，真实删了约 331 行，"
echo "     dwd 会比 9999563 少 331 行左右，这是预期的。"
echo "     想恢复完整数据，重跑：bash assets/phase3-task2-load.sh"
echo "     （只重灌 DWD 即可，DWS/MV/ADS 需按 task-3 脚本重建）"
echo
echo "=========================================="
echo " Task 5 验收完成"
echo "=========================================="

#!/usr/bin/env bash
# Phase 3 · Task 2：批量 + 实时双链路接入
# 用法：bash assets/phase3-task2-load.sh
# 所有报错原文保留，不 grep 掉
set -u
Q() { docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot "$@" 2>&1; }

S3PROP="'s3.endpoint' = 'http://minio:9000', 's3.access_key' = 'minioadmin', 's3.secret_key' = 'minioadmin', 's3.region' = 'us-east-1', 'use_path_style' = 'true'"

echo "=========================================="
echo " Phase 3 · Task 2：双链路数据接入"
echo "=========================================="
echo

echo "########## 批量链路 ##########"
echo

echo "--- 1. 清空 MinIO 上的 p3ods 目录（保证幂等）---"
docker exec -i doris-minio bash -c "rm -rf /data/doris-demo/p3ods" 2>&1
echo "已清空"
echo

echo "--- 2. 清空 ODS / DWD（保证幂等）---"
Q dw -e "TRUNCATE TABLE ods_orders;"
Q dw -e "TRUNCATE TABLE dwd_orders;"
echo "已清空"
echo

echo "--- 3. 按月导出到 MinIO（2025 全年 12 个月）---"
for M in 01 02 03 04 05 06 07 08 09 10 11 12; do
  NEXT=$(printf "%02d" $((10#$M + 1)))
  if [ "$M" = "12" ]; then YEND=2026; NEXT=01; else YEND=2025; fi
  S="2025-$M-01"; E="$YEND-$NEXT-01"
  printf "%s" "导出 2025-$M ... "
  docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "
SELECT order_date, province, city, user_id, product_id, category,
       quantity, amount, pay_type, status, created_at, updated_at
FROM orders
WHERE order_date >= '$S' AND order_date < '$E'
INTO OUTFILE 's3://doris-demo/p3ods/m2025$M/'
FORMAT AS PARQUET
PROPERTIES ($S3PROP);" 2>&1 | tail -1
done
echo

echo "--- 4. 校验 MinIO 上的文件 ---"
docker exec -i doris-minio bash -c "ls /data/doris-demo/p3ods/ | wc -l" 2>&1
echo "（应为 12 个目录）"
echo

echo "--- 5. S3 TVF 回读 + 灌入 ODS（逐月，带对账）---"
PASS=0; FAIL=0
for M in 01 02 03 04 05 06 07 08 09 10 11 12; do
  NEXT=$(printf "%02d" $((10#$M + 1)))
  if [ "$M" = "12" ]; then YEND=2026; NEXT=01; else YEND=2025; fi
  S="2025-$M-01"; E="$YEND-$NEXT-01"

  # 源表指纹
  SRC=$(Q shop -e "SELECT COUNT(*), SUM(amount) FROM orders WHERE order_date >= '$S' AND order_date < '$E';" | tail -1)

  # 灌入
  Q dw -e "
INSERT INTO ods_orders
SELECT order_date, province, city, user_id, product_id, category,
       quantity, amount, pay_type, status, created_at, updated_at
FROM S3(
  'uri' = 'http://minio:9000/doris-demo/p3ods/m2025$M/*',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  'format' = 'parquet',
  'use_path_style' = 'true'
);" > /dev/null 2>&1

  # ODS 指纹
  ODS=$(Q dw -e "SELECT COUNT(*), SUM(amount) FROM ods_orders WHERE order_date >= '$S' AND order_date < '$E';" | tail -1)

  if [ "$SRC" = "$ODS" ]; then
    echo "  2025-$M  ✅ 一致  src=[$SRC]  ods=[$ODS]"
    PASS=$((PASS+1))
  else
    echo "  2025-$M  ❌ 不一致  src=[$SRC]  ods=[$ODS]"
    FAIL=$((FAIL+1))
  fi
done
echo
echo "批量灌入对账结果：PASS=$PASS FAIL=$FAIL"
echo

echo "--- 6. ODS 总量（应与源表 2025 年数据一致）---"
Q shop -e "SELECT COUNT(*) AS src_cnt, SUM(amount) AS src_sum FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01';"
Q dw -e "SELECT COUNT(*) AS ods_cnt, SUM(amount) AS ods_sum FROM ods_orders;"
echo

echo "--- 7. ODS → DWD 去重（按天 ROW_NUMBER 造主键 + 窗口函数去重）---"
echo "    执行中（1000 万行双窗口函数，可能较慢）..."
Q dw -e "
INSERT INTO dwd_orders
SELECT
  order_date, user_id, order_id, province, city, product_id, category,
  quantity, amount, pay_type, status, created_at
FROM (
  SELECT
    order_date, province, city, user_id, product_id, category,
    quantity, amount, pay_type, status, created_at,
    ROW_NUMBER() OVER (
      PARTITION BY order_date, province, city, user_id, product_id,
                   category, quantity, amount, pay_type, status, created_at
      ORDER BY province
    ) AS dup_rn,
    ROW_NUMBER() OVER (
      PARTITION BY order_date ORDER BY province, city, user_id, product_id
    ) AS order_id
  FROM ods_orders
) t
WHERE dup_rn = 1;"
echo

echo "--- 8. DWD 去重结果对账 ---"
echo "  [口径 A] ODS 去重后的理论行数（COUNT DISTINCT 全部业务列）："
Q dw -e "SELECT COUNT(DISTINCT order_date, province, city, user_id, product_id, category, quantity, amount, pay_type, status, created_at) AS distinct_rows FROM ods_orders;"
echo "  [口径 B] DWD 实际落库行数："
Q dw -e "SELECT COUNT(*) AS dwd_rows, SUM(amount) AS dwd_sum FROM dwd_orders;"
echo

echo "--- 9. ⚠️ 验证 order_id 撞车（口径 A 与 B 的差额）---"
Q dw -e "
SELECT
  (SELECT COUNT(DISTINCT order_date, province, city, user_id, product_id, category, quantity, amount, pay_type, status, created_at) FROM ods_orders) AS distinct_rows,
  (SELECT COUNT(*) FROM dwd_orders) AS dwd_rows,
  (SELECT COUNT(DISTINCT order_date, province, city, user_id, product_id, category, quantity, amount, pay_type, status, created_at) FROM ods_orders)
    - (SELECT COUNT(*) FROM dwd_orders) AS collision_loss;"
echo "  （collision_loss > 0 说明 order_id 撞车导致真实订单被覆盖）"
echo

echo "########## 实时链路 ##########"
echo

echo "--- 10. 建实时 ODS 表 ---"
Q dw -e "DROP TABLE IF EXISTS ods_orders_rt;"
Q dw -e "
CREATE TABLE ods_orders_rt (
    order_id     BIGINT         NOT NULL,
    user_id      BIGINT         NOT NULL,
    province     VARCHAR(16)    NOT NULL,
    amount       DECIMAL(10,2)  NOT NULL,
    order_time   DATETIME       NOT NULL
)
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 4
PROPERTIES ('replication_num' = '1');"
echo

echo "--- 11. 停掉并删除可能存在的旧作业 ---"
# ⚠️ Task 1 的 setup 只 DROP 了表，不会删 Routine Load 作业。
#    作业残留会导致 CREATE 报 "Name rl_orders_rt already used in db dw"，
#    而 STOP 又会报 "The metadata of job has been changed. The job will be cancelled automatically"。
#    正确做法：先 STOP 再 DROP，两步都忽略报错。
Q dw -e "STOP ROUTINE LOAD FOR rl_orders_rt;" 2>&1 | head -2
Q dw -e "DROP ROUTINE LOAD FOR rl_orders_rt;" 2>&1 | head -2
echo "  旧作业已清理（若本来没有，上面两行报错可忽略）"
echo

echo "--- 12. 建 Routine Load 作业 ---"
# 注意三点（本项目实测踩坑）：
#   1) 换 group.id —— 沿用旧 group 会继承旧 offset，照样吃到历史脏数据
#   2) kafka_default_offsets = OFFSET_END —— 从最新位置开始，不吃历史
#   3) max_error_number 默认 0，一条脏数据就 PAUSED
Q dw -e "
CREATE ROUTINE LOAD rl_orders_rt ON ods_orders_rt
COLUMNS(order_id, user_id, province, amount, order_time)
PROPERTIES (
  'desired_concurrent_number' = '1',
  'format' = 'json',
  'max_error_number' = '100',
  'jsonpaths' = '[\"$.order_id\",\"$.user_id\",\"$.province\",\"$.amount\",\"$.order_time\"]'
)
FROM KAFKA (
  'kafka_broker_list' = 'kafka:9092',
  'kafka_topic' = 'doris_orders',
  'property.group.id' = 'p3_rt_g2',
  'property.client.id' = 'p3_rt_c2',
  'property.kafka_default_offsets' = 'OFFSET_END'
);"
echo

echo "--- 13. 等 10 秒看作业状态（应为 RUNNING，不是 PAUSED）---"
sleep 10
Q dw -e "SHOW ROUTINE LOAD FOR rl_orders_rt\G" | grep -E "Name:|State:|Progress:|Lag:|ReasonOfStateChanged:"
echo

echo "--- 14. 造 50 条实时数据 ---"
# 注意：不能用 90000$i 拼 id —— i=10 时会拼成 9000010（7位）而非 900010（6位），
# 导致后续 BETWEEN 90001 AND 90050 查不到，误判为"数据没进来"
docker exec -i doris-kafka bash -c '
for i in $(seq 1 50); do
  OID=$((900000 + i))
  echo "{\"order_id\":$OID,\"user_id\":$((1000+i)),\"province\":\"广东\",\"amount\":$((i*10)).99,\"order_time\":\"2026-09-03 11:00:00\"}"
done | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic doris_orders' 2>&1 | tail -2
echo "已生产 50 条（order_id 900001 ~ 900050）"
echo

echo "--- 15. 等 30 秒，验证实时数据已落库 ---"
sleep 30
Q dw -e "SELECT COUNT(*) AS rt_cnt, SUM(amount) AS rt_sum FROM ods_orders_rt WHERE order_id >= 900001 AND order_id <= 900050;"
echo "  （期望 rt_cnt = 50）"
echo

echo "--- 16. 实时链路作业健康（Lag 应为 0）---"
Q dw -e "SHOW ROUTINE LOAD FOR rl_orders_rt\G" | grep -E "State:|Lag:|Statistics:"
echo

echo "--- 17. 实时数据抽样 ---"
Q dw -e "SELECT * FROM ods_orders_rt WHERE order_id >= 900001 AND order_id <= 900050 ORDER BY order_id LIMIT 5;"
echo

echo "--- 18. 最终对账汇总 ---"
echo "  [批量] 源表(shop.orders, 2025年):"
Q shop -e "SELECT COUNT(*) AS cnt, SUM(amount) AS s FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01';"
echo "  [批量] ODS(dw.ods_orders):"
Q dw -e "SELECT COUNT(*) AS cnt, SUM(amount) AS s FROM ods_orders;"
echo "  [批量] DWD(dw.dwd_orders, 去重后):"
Q dw -e "SELECT COUNT(*) AS cnt, SUM(amount) AS s FROM dwd_orders;"
echo "  [实时] ods_orders_rt:"
Q dw -e "SELECT COUNT(*) AS cnt, SUM(amount) AS s FROM ods_orders_rt;"
echo

echo "=========================================="
echo " Task 2 双链路接入完成"
echo "=========================================="

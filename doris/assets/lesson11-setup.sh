#!/bin/bash
# 课 11 步骤 0：建备份仓库 + 建实验表
# 用法：bash lesson11-setup.sh
#
# 前置条件：
#   - doris-learn 容器在跑（docker ps 能看到 healthy）
#   - doris-minio 容器在跑（课 6 建的 S3 目标，bucket: doris-demo）
#   - 连 Doris：docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "===== 0. 环境检查 ====="
if ! docker ps --format '{{.Names}}' | grep -q '^doris-learn$'; then
  echo "  [FAIL] doris-learn 容器没在跑，请先启动"
  exit 1
fi
echo "  [OK] doris-learn 容器在跑"

if ! docker ps --format '{{.Names}}' | grep -q '^doris-minio$'; then
  echo "  [FAIL] doris-minio 容器没在跑（本课备份目标），请先启动"
  exit 1
fi
echo "  [OK] doris-minio 容器在跑"

# 容器能否解析 minio 主机名
if ! docker exec doris-learn getent hosts minio >/dev/null 2>&1; then
  echo "  [FAIL] doris-learn 容器解析不到 minio 主机，请确认在同一 docker 网络（doris-net）"
  exit 1
fi
echo "  [OK] 容器能解析 minio 主机"

CNT=$(q "SHOW BACKENDS\G" | grep -c "Alive: true")
echo "  [INFO] Alive 的 BE 数量: $CNT （本课备份恢复必须显式写 replication_num，原因见正文）"

echo ""
echo "===== 1. 建备份仓库（S3 指向 MinIO）====="
# 4.1.3 的 CREATE REPOSITORY 不支持 IF NOT EXISTS，已存在会报错（错误要原样展示）
q "CREATE REPOSITORY s3_repo
   WITH S3
   ON LOCATION 's3://doris-demo/backup11'
   PROPERTIES (
     's3.endpoint'     = 'http://minio:9000',
     's3.access_key'   = 'minioadmin',
     's3.secret_key'   = 'minioadmin',
     's3.region'       = 'us-east-1',
     'use_path_style'  = 'true'
   );"
echo "--- SHOW REPOSITORIES ---"
q "SHOW REPOSITORIES;"

if ! q "SHOW REPOSITORIES;" | grep -q "s3_repo"; then
  echo "  [FAIL] 仓库没建成，后续备份实验无法进行"
  exit 1
fi
echo "  [OK] 仓库 s3_repo 可用"

echo ""
echo "===== 2. 清理上一轮的实验表 ====="
for t in sc_light sc_heavy bk_orders bk_orders_r bk_part bk_part_r; do
  q "DROP TABLE IF EXISTS $t;" >/dev/null 2>&1
done
echo "  清理完成"

echo ""
echo "===== 3. 建知识点 1 的表：sc_light（开 light schema change）====="
q "CREATE TABLE sc_light (
     id      INT,
     dt      DATE,
     amount  DECIMAL(10,2)
   )
   DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 4
   PROPERTIES ('replication_num' = '1', 'light_schema_change' = 'true');"
echo "--- 确认 light_schema_change 属性 ---"
q "SHOW CREATE TABLE sc_light\G" | grep -iE "light_schema_change|replication_allocation"

echo ""
echo "===== 4. 建知识点 1 的表：sc_heavy（关 light schema change）====="
q "CREATE TABLE sc_heavy (
     id      INT,
     dt      DATE,
     amount  DECIMAL(10,2)
   )
   DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 4
   PROPERTIES ('replication_num' = '1', 'light_schema_change' = 'false');"
echo "--- 确认属性（应为 false）---"
q "SHOW CREATE TABLE sc_heavy\G" | grep -iE "light_schema_change|replication_allocation"

echo ""
echo "===== 5. 两张表各灌 500 万行 ====="
q "INSERT INTO sc_light
   SELECT number, DATE_ADD('2026-01-01', INTERVAL (number % 365) DAY), number * 1.5
   FROM numbers('number' = '5000000');"
echo "  sc_light 灌完"
q "INSERT INTO sc_heavy
   SELECT number, DATE_ADD('2026-01-01', INTERVAL (number % 365) DAY), number * 1.5
   FROM numbers('number' = '5000000');"
echo "  sc_heavy 灌完"

echo ""
echo "===== 6. 等统计稳定后确认行数 ====="
sleep 6
echo "  sc_light: $(q 'SELECT COUNT(*) FROM sc_light;' | tail -1)"
echo "  sc_heavy: $(q 'SELECT COUNT(*) FROM sc_heavy;' | tail -1)"
echo "  ⚠️ 判据用 SUM 而非 COUNT（COUNT 走元数据优化，不扫数据）:"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM sc_light;"

echo ""
echo "===== 7. 建知识点 2 的表：bk_orders（备份用，100 万行）====="
q "CREATE TABLE bk_orders (
     id      INT,
     user_id INT,
     amount  DECIMAL(10,2)
   )
   DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 4
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO bk_orders
   SELECT number, number % 10000, number * 2.5
   FROM numbers('number' = '1000000');"
sleep 5
echo "  行数与指纹（记住这组数，恢复后要对得上）:"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM bk_orders;"

echo ""
echo "===== 8. 建知识点 2 的表：bk_part（分区级备份用）====="
q "CREATE TABLE bk_part (
     dt      DATE,
     id      INT,
     v       INT
   )
   DUPLICATE KEY(dt, id)
   PARTITION BY RANGE(dt) (
     PARTITION p1 VALUES [('2026-01-01'), ('2026-02-01')),
     PARTITION p2 VALUES [('2026-02-01'), ('2026-03-01'))
   )
   DISTRIBUTED BY HASH(id) BUCKETS 2
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO bk_part SELECT '2026-01-15', number, number FROM numbers('number' = '20000');"
q "INSERT INTO bk_part SELECT '2026-02-15', number, number FROM numbers('number' = '20000');"
sleep 4
q "SELECT dt, COUNT(*) AS cnt FROM bk_part GROUP BY dt ORDER BY dt;"

echo ""
echo "===== 9. 确认当前全局设置 ====="
q "SHOW VARIABLES LIKE 'enable_sql_cache';"
q "SHOW VARIABLES LIKE 'enable_spill';"

echo ""
echo "===== setup 完成 ====="
echo "  下一步：bash lesson11-step1.sh （知识点 1：Schema Change）"

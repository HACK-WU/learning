#!/bin/bash
# 课 12 步骤 0：建实验表 + 导出共享存储对照数据
# 用法：bash lesson12-setup.sh
#
# 前置条件：
#   - doris-learn 容器在跑（docker ps 能看到 healthy）
#   - doris-minio 容器在跑（课 6 建的 S3 目标，bucket: doris-demo）
#   - orders 表在（2150 万行，课 2/课 3 建的）
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
  echo "  [FAIL] doris-minio 容器没在跑（本课共享存储目标），请先启动"
  exit 1
fi
echo "  [OK] doris-minio 容器在跑"

if ! docker exec doris-learn getent hosts minio >/dev/null 2>&1; then
  echo "  [FAIL] doris-learn 容器解析不到 minio 主机，请确认在同一 docker 网络（doris-net）"
  exit 1
fi
echo "  [OK] 容器能解析 minio 主机"

echo ""
echo "===== 1. 确认 orders 表可用（本课大部分数据从它派生）====="
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM orders;"
q "SELECT MIN(order_date) AS min_d, MAX(order_date) AS max_d FROM orders;"

echo ""
echo "===== 2. 清理上一轮的实验表 ====="
for t in anti_kv log_search local_1m; do
  q "DROP TABLE IF EXISTS $t;" >/dev/null 2>&1
done
echo "  清理完成"

echo ""
echo "===== 3. 建知识点 1 的表：local_1m（列存聚合基线，本地存储）====="
echo "  用确定性谓词（2025 Q1），保证与导出到共享存储的 parquet 完全同口径"
q "CREATE TABLE local_1m (
     order_date DATE NULL,
     province   VARCHAR(16) NULL,
     city       VARCHAR(32) NULL,
     user_id    BIGINT NULL,
     product_id INT NULL,
     category   VARCHAR(32) NULL,
     quantity   INT NULL,
     amount     DECIMAL(10,2) NULL,
     pay_type   VARCHAR(16) NULL,
     status     TINYINT NULL
   )
   DUPLICATE KEY(order_date, province, city, user_id)
   DISTRIBUTED BY HASH(province) BUCKETS 4
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO local_1m
   SELECT order_date, province, city, user_id, product_id,
          category, quantity, amount, pay_type, status
   FROM orders
   WHERE order_date >= '2025-01-01' AND order_date < '2025-04-01';"
sleep 6
echo "  本地表指纹（记住这组数，要和共享存储侧对得上）:"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM local_1m;"

echo ""
echo "===== 4. 建反模式实验表：anti_kv（UNIQUE KEY，模拟当 KV 用）====="
q "CREATE TABLE anti_kv (
     id     BIGINT NOT NULL,
     mobile VARCHAR(32) NOT NULL,
     name   VARCHAR(64) NULL,
     amount DECIMAL(18,2) NULL
   )
   UNIQUE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 4
   PROPERTIES ('replication_num' = '1', 'enable_unique_key_merge_on_write' = 'true');"
q "INSERT INTO anti_kv
   SELECT user_id,
          CONCAT('138', LPAD(CAST(user_id AS STRING), 8, '0')),
          'user_name',
          amount
   FROM orders LIMIT 500000;"
sleep 6
echo "  ⚠️ 注意：UNIQUE KEY 按 id(user_id) 去重，50 万行源数据去重后行数会变少"
echo "  这是真实行为，正文会解释为什么「用 Doris 做主键去重存储」是设计失误："
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM anti_kv;"

echo ""
echo "===== 5. 建知识点 1 的表：log_search（倒排索引，模拟抢 ES 场景）====="
echo "  ⚠️ parser 用 english，不用 chinese —— 本机 BE 缺 jieba 字典，实测报："
echo "     chinese tokenizer dict file not found: /opt/be2/dict/jieba.dict.utf8"
q "CREATE TABLE log_search (
     ts    DATETIME NULL,
     level VARCHAR(16) NULL,
     msg   STRING NULL,
     INDEX idx_msg (msg) USING INVERTED PROPERTIES('parser' = 'english', 'support_phrase' = 'true'),
     INDEX idx_level (level) USING INVERTED
   )
   DUPLICATE KEY(ts)
   DISTRIBUTED BY HASH(ts) BUCKETS 2
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO log_search
   SELECT created_at,
          CASE WHEN user_id % 10 = 0 THEN 'ERROR'
               WHEN user_id % 3  = 0 THEN 'WARN'
               ELSE 'INFO' END,
          CONCAT('user ', CAST(user_id AS STRING), ' bought ',
                 category, ' in city ', CAST(product_id AS STRING),
                 ' amount ', CAST(amount AS STRING))
   FROM orders LIMIT 200000;"
sleep 6
q "SELECT COUNT(*) AS cnt, SUM(LENGTH(msg)) AS total_len FROM log_search;"
echo "  ⚠️ 这个 sleep 6 是必要的：INSERT 后统计信息需要几秒才刷新，"
echo "     紧跟 INSERT 查询可能返回 0（课 8 踩过的坑）"

echo ""
echo "===== 6. 导出同口径数据到共享存储（MinIO），用于知识点 2 的本地性对比 ====="
docker exec doris-minio sh -c "rm -rf /data/doris-demo/l12/*" 2>&1
q "SELECT order_date, province, city, user_id, product_id,
          category, quantity, amount, pay_type, status
   FROM orders
   WHERE order_date >= '2025-01-01' AND order_date < '2025-04-01'
   INTO OUTFILE 's3://doris-demo/l12/orders_q1_'
   FORMAT AS PARQUET
   PROPERTIES (
     's3.endpoint'   = 'http://minio:9000',
     's3.access_key' = 'minioadmin',
     's3.secret_key' = 'minioadmin',
     's3.region'     = 'us-east-1',
     'use_path_style' = 'true'
   );"

echo ""
echo "===== 7. 校验：共享存储侧与本地侧必须完全同口径 ====="
echo "--- 本地表 local_1m ---"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM local_1m;"
echo "--- 共享存储（MinIO 上的 parquet，用 S3 TVF 读）---"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM S3(
     'uri' = 'http://minio:9000/doris-demo/l12/*',
     's3.access_key' = 'minioadmin',
     's3.secret_key' = 'minioadmin',
     's3.region' = 'us-east-1',
     'use_path_style' = 'true',
     'format' = 'parquet');"
echo "  ⚠️ 两边 cnt 与 sum_amt 必须完全一致，否则后续性能对比无意义"

echo ""
echo "===== 8. 确认当前全局设置 ====="
q "SHOW VARIABLES LIKE 'enable_sql_cache';"
echo "  （课 7 关的，测性能必须保持关闭；正文里会提醒这是为什么）"

echo ""
echo "===== setup 完成 ====="
echo "  下一步：bash lesson12-step1.sh （知识点 1：Doris 与同类系统对比）"

#!/bin/bash
# 课 12 评审 1（learner 视角）：逐条实跑正文里的 SQL，验证「读者照抄能跑通吗」
# 重点查：正文里的每条 DDL/DML 是否完整、是否可执行、结果是否与正文描述一致

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "############ A. 第二幕的两条对比查询（正文 1.2 节）############"
echo ""
echo "--- A1: 扫 1 列 ---"
q "SELECT SUM(amount) FROM orders;"
echo "--- A2: 扫 13 列 ---"
q "SELECT SUM(LENGTH(CONCAT(CAST(order_date AS STRING), province, city,
  CAST(user_id AS STRING), CAST(product_id AS STRING), category,
  CAST(quantity AS STRING), CAST(amount AS STRING), pay_type,
  CAST(status AS STRING), remark, CAST(created_at AS STRING),
  CAST(updated_at AS STRING)))) FROM orders;"
echo "  ⚠️ 核对：正文写『列数翻 13 倍，耗时翻 4 倍』，需确认 orders 是不是 13 列"
q "DESC orders;" | wc -l

echo ""
echo "############ B. 1.3 节 log_search 建表语句（照抄测试）############"
q "DROP TABLE IF EXISTS rv_log_search;"
q "CREATE TABLE rv_log_search (
     ts    DATETIME NULL,
     level VARCHAR(16) NULL,
     msg   STRING NULL,
     INDEX idx_msg (msg) USING INVERTED PROPERTIES('parser' = 'english', 'support_phrase' = 'true'),
     INDEX idx_level (level) USING INVERTED
   )
   DUPLICATE KEY(ts)
   DISTRIBUTED BY HASH(ts) BUCKETS 2
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO rv_log_search
   SELECT created_at,
          CASE WHEN user_id % 10 = 0 THEN 'ERROR'
               WHEN user_id % 3  = 0 THEN 'WARN'
               ELSE 'INFO' END,
          CONCAT('user ', CAST(user_id AS STRING), ' bought ',
                 category, ' in city ', CAST(product_id AS STRING),
                 ' amount ', CAST(amount AS STRING))
   FROM orders LIMIT 200000;"
sleep 5
q "SELECT COUNT(*) AS cnt, SUM(LENGTH(msg)) AS total_len FROM rv_log_search;"

echo ""
echo "############ C. 1.3 节 chinese parser 报错（核对是否可复现）############"
q "DROP TABLE IF EXISTS rv_log_cn;"
q "CREATE TABLE rv_log_cn (
     ts  DATETIME NULL,
     msg STRING NULL,
     INDEX idx_msg (msg) USING INVERTED PROPERTIES('parser' = 'chinese', 'support_phrase' = 'true')
   ) DUPLICATE KEY(ts) DISTRIBUTED BY HASH(ts) BUCKETS 1
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO rv_log_cn SELECT created_at, CONCAT('用户在', city, '购买了', category) FROM orders LIMIT 1000;"
q "SELECT COUNT(*) FROM rv_log_cn WHERE msg MATCH_ANY '北京';"

echo ""
echo "############ D. 1.3 节 MATCH_PHRASE 严格相邻（核对）############"
q "SELECT SUM(LENGTH(msg)) AS len_sum FROM rv_log_search WHERE msg MATCH_PHRASE 'bought';"
q "SELECT SUM(LENGTH(msg)) AS len_sum FROM rv_log_search WHERE msg MATCH_PHRASE 'user bought';"
q "SELECT msg FROM rv_log_search LIMIT 2;"

echo ""
echo "############ E. 1.5 节 转账 ROLLBACK（正文核心反模式）############"
q "DROP TABLE IF EXISTS rv_anti_txn2;"
q "CREATE TABLE rv_anti_txn2 (
     id     BIGINT NOT NULL,
     amount DECIMAL(18,2) NULL,
     memo   VARCHAR(64) NULL
   ) UNIQUE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2
   PROPERTIES ('replication_num' = '1', 'enable_unique_key_merge_on_write' = 'true');"
q "INSERT INTO rv_anti_txn2 VALUES (1, 100.00, 'init');"
q "BEGIN;"
q "UPDATE rv_anti_txn2 SET amount = amount - 30 WHERE id = 1;"
q "INSERT INTO rv_anti_txn2 VALUES (2, 30.00, 'from_1');"
q "ROLLBACK;"
echo "  ⚠️ 核对：正文写『id=1 amount=70.00，id=2 amount=30.00』"
q "SELECT id, amount, memo FROM rv_anti_txn2 ORDER BY id;"

echo ""
echo "############ F. 小测 2 的 t_rollback 建表语句（照抄测试）############"
q "DROP TABLE IF EXISTS t_rollback;"
q "CREATE TABLE t_rollback (
     id BIGINT NOT NULL, amount DECIMAL(18,2) NULL, memo VARCHAR(64) NULL
   ) UNIQUE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 2
   PROPERTIES ('replication_num' = '1', 'enable_unique_key_merge_on_write' = 'true');"
q "INSERT INTO t_rollback VALUES (1, 100.00, 'init');"
q "BEGIN;"
q "UPDATE t_rollback SET amount = amount - 30 WHERE id = 1;"
q "INSERT INTO t_rollback VALUES (2, 30.00, 'from_1');"
q "ROLLBACK;"
q "SELECT id, amount, memo FROM t_rollback ORDER BY id;"

echo ""
echo "############ G. 2.3 节 S3 TVF 语句（照抄测试）############"
q "SELECT COUNT(*) AS cnt, SUM(amount) AS sum_amt FROM S3(
     'uri' = 'http://minio:9000/doris-demo/l12/*',
     's3.access_key' = 'minioadmin',
     's3.secret_key' = 'minioadmin',
     's3.region' = 'us-east-1',
     'use_path_style' = 'true',
     'format' = 'parquet');"

echo ""
echo "############ H. 2.3 节 S3 TVF 三个坑（核对报错是否可复现）############"
echo "--- H1: 缺 uri ---"
q "SELECT COUNT(*) FROM S3(
     's3.endpoint' = 'http://minio:9000',
     's3.access_key' = 'minioadmin',
     's3.secret_key' = 'minioadmin',
     's3.region' = 'us-east-1',
     's3.bucket' = 'doris-demo',
     's3.root.path' = 'orders_10k.csv',
     'use_path_style' = 'true',
     'format' = 'csv_with_names');"
echo "--- H2: 缺 use_path_style ---"
q "SELECT COUNT(*) FROM S3(
     'uri' = 'http://minio:9000/doris-demo/orders_10k.csv',
     's3.access_key' = 'minioadmin',
     's3.secret_key' = 'minioadmin',
     'format' = 'csv_with_names');"
echo "--- H3: csv_schema 类型 ---"
q "SELECT COUNT(*) FROM S3(
     'uri' = 'http://minio:9000/doris-demo/orders_10k.csv',
     's3.access_key' = 'minioadmin', 's3.secret_key' = 'minioadmin',
     's3.region' = 'us-east-1', 'use_path_style' = 'true',
     'format' = 'csv', 'column_separator' = ',',
     'csv_schema' = 'order_id:bigint;province:varchar(32)');"
echo "--- H4: CREATE EXTERNAL TABLE ENGINE=S3 ---"
q "DROP TABLE IF EXISTS rv_s3_ext;"
q "CREATE EXTERNAL TABLE rv_s3_ext (
     order_id BIGINT NULL, province VARCHAR(32) NULL
   ) ENGINE=S3
   PROPERTIES (
     's3.endpoint' = 'http://minio:9000',
     's3.access_key' = 'minioadmin',
     's3.secret_key' = 'minioadmin',
     's3.region' = 'us-east-1',
     's3.bucket' = 'doris-demo',
     's3.root.path' = 'orders_10k.csv',
     'format' = 'csv_with_names');"

echo ""
echo "############ I. 3.6 节分区反模式（核对 orders 是单分区）############"
q "SHOW PARTITIONS FROM orders;" | awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="PartitionName")p=i;if($i=="RowCount")r=i};next}{printf "   分区=%-16s 行数=%s\n",$p,$r}'

echo ""
echo "############ J. 2.2 节 cloud mode 报错（核对）############"
q "SHOW COMPUTE GROUPS;"
q "SHOW STORAGE VAULT;"
q "SHOW CACHE HOTSPOTS;"

echo ""
echo "############ K. 清理评审表 ############"
for t in rv_log_search rv_log_cn rv_anti_txn2 t_rollback rv_s3_ext; do
  q "DROP TABLE IF EXISTS $t;" >/dev/null 2>&1
done
echo "  清理完成"

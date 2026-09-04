#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
mkdir -p /tmp/loadlab
S3TVF="'uri' = 'http://minio:9000/doris-demo/orders_10k.csv',
  'format' = 'csv',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  's3.region' = 'us-east-1',
  'minio.endpoint' = 'http://minio:9000',
  'use_path_style' = 'true',
  'column_separator' = ',',
  'csv_schema' = 'order_id:bigint;user_id:bigint;province:string;city:string;category:string;amount:decimal(10,2);pay_type:int;order_date:date'"

echo "############ 1. TVF 读出来列名是什么 ############"
Q "SELECT order_id, province, amount, order_date FROM s3($S3TVF) LIMIT 3"

echo ""
echo "############ 2. INSERT INTO ... FROM s3()（1 万行）############"
Q "TRUNCATE TABLE s3_orders_ext"
S=$(date +%s.%N)
Q "INSERT INTO s3_orders_ext SELECT order_id, user_id, province, city, category, amount, pay_type, order_date FROM s3($S3TVF)"
E=$(date +%s.%N)
echo "S3 批量拉取（1 万行）端到端: $(echo "$E - $S" | bc) 秒"
Q "SELECT COUNT(*) AS rows_loaded FROM s3_orders_ext"
Q "SELECT * FROM s3_orders_ext LIMIT 3"

echo ""
echo "############ 3. 一次性拉 batch/ 整个目录（2 万行）############"
Q "TRUNCATE TABLE s3_orders_ext"
S2=$(date +%s.%N)
Q "INSERT INTO s3_orders_ext SELECT order_id, user_id, province, city, category, amount, pay_type, order_date FROM s3(
  'uri' = 'http://minio:9000/doris-demo/batch/*',
  'format' = 'csv',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  's3.region' = 'us-east-1',
  'minio.endpoint' = 'http://minio:9000',
  'use_path_style' = 'true',
  'column_separator' = ',',
  'csv_schema' = 'order_id:bigint;user_id:bigint;province:string;city:string;category:string;amount:decimal(10,2);pay_type:int;order_date:date'
)"
E2=$(date +%s.%N)
echo "S3 批量拉取（目录 2 万行）端到端: $(echo "$E2 - $S2" | bc) 秒"
Q "SELECT COUNT(*) AS rows_from_dir FROM s3_orders_ext"

echo ""
echo "############ 4. Stream Load（1 万行）对照组 ############"
Q "TRUNCATE TABLE load_demo"
S3=$(date +%s.%N)
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_final_$RANDOM" -H "column_separator:," -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "http://127.0.0.1:8030/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows|LoadTimeMs)"'
E3=$(date +%s.%N)
echo "Stream Load（1 万行）端到端: $(echo "$E3 - $S3" | bc) 秒"

echo ""
echo "############ 5. 小批量高频对照组（1000 次单行 INSERT 之前已测：34.4 秒）############"
echo "（见 lesson06-strictmode-bench.sh 实验 C1）"

echo ""
echo "############ 6. INSERT INTO ... SELECT（库内表到表）############"
Q "TRUNCATE TABLE load_demo"
S4=$(date +%s.%N)
Q "INSERT INTO load_demo SELECT order_id, user_id, province, city, category, amount, pay_type, order_date FROM s3_orders_ext LIMIT 10000"
E4=$(date +%s.%N)
echo "INSERT INTO SELECT（1 万行，库内）: $(echo "$E4 - $S4" | bc) 秒"
Q "SELECT COUNT(*) FROM load_demo"

echo ""
echo "############ 7. 最终各表行数总览 ############"
Q "SELECT 'load_demo' AS tbl, COUNT(*) AS rows FROM load_demo
   UNION ALL SELECT 's3_orders_ext', COUNT(*) FROM s3_orders_ext
   UNION ALL SELECT 'kafka_orders', COUNT(*) FROM kafka_orders"

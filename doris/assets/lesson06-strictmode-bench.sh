#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
FE_HTTP="http://127.0.0.1:8030"
mkdir -p /tmp/loadlab

echo "############ A. 确认 strict_mode 默认值 ############"
echo "--- A1: 不设 strict_mode，导入 amount='123abc' ---"
docker exec doris-learn bash -c "printf '700001,111,广东,测试市,手机,123abc,1,2024-01-15\n' > /tmp/loadlab/one_bad2.csv"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_default_mode" -H "column_separator:," -H "format:csv" \
  -H "max_filter_ratio:1" \
  -T /tmp/loadlab/one_bad2.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows)"'
echo "--- 落库值（若 amount=NULL 说明默认 strict_mode=false，脏值静默变 NULL）---"
Q "SELECT order_id, amount, city FROM load_demo WHERE order_id=700001"

echo ""
echo "--- A2: 显式 strict_mode:true 同一行 ---"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_sm_true" -H "column_separator:," -H "format:csv" \
  -H "strict_mode:true" -H "max_filter_ratio:1" \
  -T /tmp/loadlab/one_bad2.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows)"'

echo ""
echo "############ B. 脏数据 + strict_mode:true + max_filter_ratio=0 → 整批失败（原子性）############"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_base2" -H "column_separator:," -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows)"'
Q "SELECT COUNT(*) AS baseline FROM load_demo"

echo ""
echo "--- B1: max_filter_ratio=0（严格）导入 1000 行含 50 行脏 ---"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_dirty_r0" -H "column_separator:," -H "format:csv" \
  -H "strict_mode:true" -H "max_filter_ratio:0" \
  -T /tmp/loadlab/orders_dirty.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | tee /tmp/loadlab/rb1.json | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows)"'
grep -E '"Message"' /tmp/loadlab/rb1.json
echo "--- 行数应仍为 10000（整批回滚，一条没进）---"
Q "SELECT COUNT(*) AS after_r0 FROM load_demo"

echo ""
echo "--- B2: max_filter_ratio=0.1（容错 10%）导入同一文件 ---"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_dirty_r01" -H "column_separator:," -H "format:csv" \
  -H "strict_mode:true" -H "max_filter_ratio:0.1" \
  -T /tmp/loadlab/orders_dirty.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | tee /tmp/loadlab/rb2.json | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows|NumberUnselectedRows)"'
echo "--- 行数应变为 10950 ---"
Q "SELECT COUNT(*) AS after_r01 FROM load_demo"

echo ""
echo "--- B3: 取 ErrorURL 看脏数据原因 ---"
ERRURL=$(grep '"ErrorURL"' /tmp/loadlab/rb2.json | sed 's/.*"ErrorURL": *"\([^"]*\)".*/\1/')
echo "ErrorURL: $ERRURL"
if [ -n "$ERRURL" ]; then
  docker exec doris-learn curl -s "$ERRURL" | head -8
fi

echo ""
echo "############ C. 小批量高频 vs 一次批量（第二幕认知冲突的核心证据）############"
Q "TRUNCATE TABLE load_demo"

echo "--- C1: 1000 次单行 INSERT（模拟小批量高频写入）---"
S1=$(date +%s.%N)
docker exec doris-learn bash -c "
for i in \$(seq 1 1000); do
  mysql -h 127.0.0.1 -P 9030 -uroot shop -e \"INSERT INTO load_demo VALUES (\$i, \$i, '广东', '广州', '手机', 99.90, 1, '2024-01-15');\" 2>/dev/null
done
"
E1=$(date +%s.%N)
echo "1000 次单行 INSERT 耗时: $(echo "$E1 - $S1" | bc) 秒"
Q "SELECT COUNT(*) AS rows_after_single_insert FROM load_demo"

echo ""
echo "--- C2: 1 次批量 INSERT INTO ... VALUES（1000 行一次性）---"
Q "TRUNCATE TABLE load_demo"
S2=$(date +%s.%N)
docker exec doris-learn bash -c "
VALS=''
for i in \$(seq 1 1000); do
  if [ -n \"\$VALS\" ]; then VALS=\"\$VALS,\"; fi
  VALS=\"\$VALS(\$i,\$i,'广东','广州','手机',99.90,1,'2024-01-15')\"
done
mysql -h 127.0.0.1 -P 9030 -uroot shop -e \"INSERT INTO load_demo VALUES \$VALS;\" 2>&1 | grep -vE '^Warning|Using a password'
"
E2=$(date +%s.%N)
echo "1 次批量 INSERT（1000 行）耗时: $(echo "$E2 - $S2" | bc) 秒"
Q "SELECT COUNT(*) AS rows_after_batch_insert FROM load_demo"

echo ""
echo "--- C3: 1 次 Stream Load（同样的 1 万行 CSV）---"
Q "TRUNCATE TABLE load_demo"
S3=$(date +%s.%N)
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_perf" -H "column_separator:," -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows|LoadTimeMs|CommitAndPublishTimeMs)"'
E3=$(date +%s.%N)
echo "1 次 Stream Load（1 万行）端到端耗时: $(echo "$E3 - $S3" | bc) 秒"
Q "SELECT COUNT(*) AS rows_after_stream_load FROM load_demo"

echo ""
echo "############ D. 看事务堆积：导入产生的 tablet 版本数 ############"
Q "SHOW TABLETS FROM load_demo LIMIT 3"
echo ""
echo "--- 各分区行数 ---"
Q "SELECT PARTITION_NAME, TABLET_NUM, ROW_COUNT FROM information_schema.partitions WHERE TABLE_NAME='load_demo'"

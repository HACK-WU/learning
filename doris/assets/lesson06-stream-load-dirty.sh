#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
FE_HTTP="http://127.0.0.1:8030"
mkdir -p /tmp/loadlab

echo "############ 准备：清空表，导入干净基线 ############"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_base" -H "column_separator:," -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows)"'
Q "SELECT COUNT(*) AS baseline FROM load_demo"

echo ""
echo "############ 实验 5：脏数据 + max_filter_ratio=0（默认严格 → 整批失败）############"
echo "--- 脏数据文件：1000 行，其中 50 行 amount='NOT_A_NUMBER'（占 5%）---"
docker exec doris-learn bash -c "grep -c 'NOT_A_NUMBER' /tmp/loadlab/orders_dirty.csv"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_dirty_strict" \
  -H "column_separator:," \
  -H "format:csv" \
  -H "max_filter_ratio:0" \
  -T /tmp/loadlab/orders_dirty.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | tee /tmp/loadlab/r_strict.json | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows)"'
echo ""
echo "--- 关键：Status 与 Message ---"
grep -E '"(Status|Message)"' /tmp/loadlab/r_strict.json
echo ""
echo "--- 原子性验证：行数应仍为 10000（一条都没进）---"
Q "SELECT COUNT(*) AS after_strict FROM load_demo"

echo ""
echo "############ 实验 6：同一批脏数据 + max_filter_ratio=0.1（容错 → 成功）############"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_dirty_tolerant" \
  -H "column_separator:," \
  -H "format:csv" \
  -H "max_filter_ratio:0.1" \
  -T /tmp/loadlab/orders_dirty.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | tee /tmp/loadlab/r_tol.json | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows|NumberUnselectedRows)"'
echo ""
echo "--- 行数应变为 10950（10000 + 950 行合格）---"
Q "SELECT COUNT(*) AS after_tolerant FROM load_demo"

echo ""
echo "############ 实验 7：脏数据原因追踪（ErrorURL）############"
ERRURL=$(grep '"ErrorURL"' /tmp/loadlab/r_tol.json | sed 's/.*"ErrorURL": *"\([^"]*\)".*/\1/')
echo "ErrorURL: $ERRURL"
if [ -n "$ERRURL" ]; then
  echo "--- 取回错误详情 ---"
  docker exec doris-learn curl -s "$ERRURL" | head -10
fi

echo ""
echo "############ 实验 8：strict_mode 对字符串转数字的影响 ############"
echo "--- 8a: strict_mode=true（默认）导入 amount='123abc' ---"
docker exec doris-learn bash -c "printf '900001,111,广东,测试市,手机,123abc,1,2024-01-15\n' > /tmp/loadlab/one_bad.csv"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_strict_on" -H "column_separator:," -H "format:csv" \
  -H "strict_mode:true" -H "max_filter_ratio:1" \
  -T /tmp/loadlab/one_bad.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows)"'

echo ""
echo "--- 8b: strict_mode=false 导入同一行 ---"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_strict_off" -H "column_separator:," -H "format:csv" \
  -H "strict_mode:false" -H "max_filter_ratio:1" \
  -T /tmp/loadlab/one_bad.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows)"'

echo ""
echo "--- 8b 结果：那行到底写成什么了？ ---"
Q "SELECT order_id, amount FROM load_demo WHERE order_id=900001"

echo ""
echo "############ 实验 9：列映射（CSV 列顺序与表不一致）############"
echo "--- CSV 只有 4 列：order_id, amount, province, order_date ---"
docker exec doris-learn bash -c "printf '800001,999.99,广东,2024-01-20\n800002,888.88,山东,2024-02-20\n' > /tmp/loadlab/partial.csv"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_colmap" -H "column_separator:," -H "format:csv" \
  -H "columns:order_id,amount,province,order_date" \
  -T /tmp/loadlab/partial.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberTotalRows|NumberLoadedRows)"'
echo ""
Q "SELECT * FROM load_demo ORDER BY order_id"

#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
FE_HTTP="http://127.0.0.1:8030"
mkdir -p /tmp/loadlab

echo "############ 0. 重建干净测试数据 ############"
Q "TRUNCATE TABLE load_demo"

docker exec doris-learn bash -c "
mkdir -p /tmp/loadlab
awk 'BEGIN{
  srand(42);
  split(\"广东,山东,江苏,浙江,四川,北京,上海,福建\",prov,\",\");
  split(\"广州,深圳,青岛,济南,南京,苏州,杭州,宁波,成都,绵阳,北京,上海,厦门,福州\",ct,\",\");
  split(\"手机,电脑,家电,服饰,食品\",cat,\",\");
  for(i=1;i<=10000;i++){
    p=prov[int(rand()*8)+1];
    c=ct[int(rand()*14)+1];
    k=cat[int(rand()*5)+1];
    d=(i%28)+1; m=(i%2)+1;
    printf \"%d,%d,%s,%s,%s,%.2f,%d,2024-%02d-%02d\n\", i, int(rand()*500000)+1, p, c, k, rand()*5000+10, int(rand()*4)+1, m, d;
  }
}' > /tmp/loadlab/orders_10k.csv
echo '--- CSV 前 3 行 ---'
head -3 /tmp/loadlab/orders_10k.csv
echo '--- CSV 行数 ---'
wc -l < /tmp/loadlab/orders_10k.csv
echo '--- 日期合法性校验（应有 0 条非法）---'
awk -F, '\$8 !~ /^2024-(0[12])-(0[1-9]|1[0-9]|2[0-8])\$/ {c++} END{print \"非法日期行数: \" c+0}' /tmp/loadlab/orders_10k.csv
"

echo ""
echo "############ 实验 1：CSV 成功导入 ############"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_csv_10k" \
  -H "column_separator:," \
  -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | tee /tmp/loadlab/r1.json
echo ""
echo "--- 落库行数 ---"
Q "SELECT COUNT(*) FROM load_demo"

echo ""
echo "############ 实验 2：同 Label 重复提交（幂等去重）############"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_csv_10k" \
  -H "column_separator:," \
  -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | tee /tmp/loadlab/r2.json
echo ""
echo "--- 行数应仍为 10000（幂等生效）---"
Q "SELECT COUNT(*) FROM load_demo"

echo ""
echo "############ 实验 3：不同 Label 重复导入同样数据（不去重，变 2 万）############"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_csv_10k_again" \
  -H "column_separator:," \
  -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows)"'
echo ""
echo "--- 行数应变 20000 ---"
Q "SELECT COUNT(*) FROM load_demo"

echo ""
echo "############ 实验 4：JSON 导入（NDJSON）############"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_json_1k" \
  -H "format:json" \
  -H "read_json_by_line:true" \
  -T /tmp/loadlab/orders_1k.json \
  "$FE_HTTP/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberTotalRows|NumberLoadedRows|NumberFilteredRows)"'
echo ""
echo "--- 行数应为 1000 ---"
Q "SELECT COUNT(*) FROM load_demo"

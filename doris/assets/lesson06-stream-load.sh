#!/bin/bash
echo "=== 1. 为导入实验建一张目标表（Duplicate，按天分区）==="
docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "
DROP TABLE IF EXISTS load_demo;
CREATE TABLE load_demo (
    order_id    BIGINT,
    user_id     BIGINT,
    province    VARCHAR(32),
    city        VARCHAR(64),
    category    VARCHAR(32),
    amount      DECIMAL(10,2),
    pay_type    TINYINT,
    order_date  DATE
)
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01')),
    PARTITION pother  VALUES [('2024-03-01'), ('2025-01-01'))
)
DISTRIBUTED BY HASH(order_id) BUCKETS 4
PROPERTIES ('replication_num' = '1');
" 2>&1 | grep -vE "^Warning|Using a password"
echo "建表返回码: $?"

echo ""
echo "=== 2. 确认表结构 ==="
docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "SHOW CREATE TABLE load_demo\G" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 3. 生成测试 CSV（1 万行）到 WSL /tmp ==="
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
    d=(i%60)+1; m=(i%2)+1;
    printf \"%d,%d,%s,%s,%s,%.2f,%d,2024-%02d-%02d\n\", i, int(rand()*500000)+1, p, c, k, rand()*5000+10, int(rand()*4)+1, m, d;
  }
}' > /tmp/loadlab/orders_10k.csv
wc -l /tmp/loadlab/orders_10k.csv
head -3 /tmp/loadlab/orders_10k.csv
"

echo ""
echo "=== 4. 生成 JSON 测试文件（1000 行，NDJSON）==="
docker exec doris-learn bash -c "
awk 'BEGIN{
  srand(7);
  split(\"广东,山东,江苏,浙江,四川\",prov,\",\");
  split(\"手机,电脑,家电,服饰,食品\",cat,\",\");
  for(i=1;i<=1000;i++){
    p=prov[int(rand()*5)+1];
    k=cat[int(rand()*5)+1];
    d=(i%28)+1; m=(i%2)+1;
    printf \"{\\\"order_id\\\":%d,\\\"user_id\\\":%d,\\\"province\\\":\\\"%s\\\",\\\"city\\\":\\\"%s\\\",\\\"category\\\":\\\"%s\\\",\\\"amount\\\":%.2f,\\\"pay_type\\\":%d,\\\"order_date\\\":\\\"2024-%02d-%02d\\\"}\n\", i+1000000, int(rand()*500000)+1, p, p\"市\", k, rand()*3000+10, int(rand()*4)+1, m, d;
  }
}' > /tmp/loadlab/orders_1k.json
wc -l /tmp/loadlab/orders_1k.json
head -2 /tmp/loadlab/orders_1k.json
"

echo ""
echo "=== 5. 生成含 5% 脏数据的 CSV（验证 max_filter_ratio）==="
docker exec doris-learn bash -c "
awk 'BEGIN{
  srand(11);
  split(\"广东,山东,江苏\",prov,\",\");
  for(i=1;i<=1000;i++){
    if(i%20==0){
      printf \"%d,%d,%s,%s,%s,NOT_A_NUMBER,%d,2024-01-15\n\", i, i, prov[1], \"测试市\", \"手机\", int(rand()*4)+1;
    } else {
      printf \"%d,%d,%s,%s,%s,%.2f,%d,2024-01-15\n\", i, int(rand()*100000)+1, prov[int(rand()*3)+1], \"测试市\", \"手机\", rand()*1000+10, int(rand()*4)+1;
    }
  }
}' > /tmp/loadlab/orders_dirty.csv
wc -l /tmp/loadlab/orders_dirty.csv
echo '--- 脏数据样例（第 20 行 amount=NOT_A_NUMBER）---'
sed -n '20p' /tmp/loadlab/orders_dirty.csv
"

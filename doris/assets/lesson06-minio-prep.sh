#!/bin/bash
set -x
echo "=== 用 curl 通过 MinIO API 建 bucket（无 mc 客户端时）==="
docker exec doris-learn bash -c "
# 建 bucket：用 S3 REST API + 匿名签名太麻烦，改用 MinIO 自带的 mc（在 minio 容器里）
echo 'skip'
"

echo ""
echo "=== 在 minio 容器内用 mc 建 bucket 并上传 ==="
docker exec doris-minio bash -c "
which mc && echo 'MC_EXISTS' || echo 'MC_MISSING'
"

echo ""
echo "=== 检查 minio 容器内的目录 ==="
docker exec doris-minio bash -c "ls /data 2>/dev/null; ls /opt/bin 2>/dev/null | head"

echo ""
echo "=== 用 curl 创建 bucket（MinIO 支持匿名 PUT 创建需策略，改用 Python/awk 造签名，或与 Doris 直接测）==="
echo "=== 先看 Doris 是否支持 S3 TVF（Broker Load 的现代替代）==="
docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "SHOW BROKER;" 2>&1 | grep -vE "^Warning|Using a password"

echo ""
echo "=== 检查 S3 TVF 可用性 ==="
docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "
SELECT count(*) FROM s3(
  'uri' = 'http://minio:9000/doris-demo/orders_10k.csv',
  'format' = 'csv',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  'column_separator' = ','
);
" 2>&1 | grep -vE "^Warning|Using a password"

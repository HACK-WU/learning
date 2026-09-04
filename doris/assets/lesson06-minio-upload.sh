#!/bin/bash
set -x
echo "=== 1. 在 minio 容器内解压 mc 客户端 ==="
docker exec doris-minio bash -c "cd /opt/bin && gunzip -c mc.gz > /tmp/mc && chmod +x /tmp/mc && /tmp/mc --version" 2>&1 | tail -3

echo ""
echo "=== 2. 配置 mc alias ==="
docker exec doris-minio bash -c "/tmp/mc alias set local http://127.0.0.1:9000 minioadmin minioadmin" 2>&1 | tail -3

echo ""
echo "=== 3. 建 bucket doris-demo ==="
docker exec doris-minio bash -c "/tmp/mc mb local/doris-demo --ignore-existing" 2>&1 | tail -3

echo ""
echo "=== 4. 从 doris-learn 拷贝 CSV 到本机再推到 minio ==="
# 先把 doris-learn 内的文件拷到 WSL /tmp
docker cp doris-learn:/tmp/loadlab/orders_10k.csv /tmp/orders_10k.csv
ls -la /tmp/orders_10k.csv

echo ""
echo "=== 5. 把文件复制到 minio 容器并上传 ==="
docker cp /tmp/orders_10k.csv doris-minio:/tmp/orders_10k.csv
docker exec doris-minio bash -c "/tmp/mc cp /tmp/orders_10k.csv local/doris-demo/orders_10k.csv" 2>&1 | tail -3

echo ""
echo "=== 6. 再传一份 JSON ==="
docker cp doris-learn:/tmp/loadlab/orders_1k.json /tmp/orders_1k.json
docker cp /tmp/orders_1k.json doris-minio:/tmp/orders_1k.json
docker exec doris-minio bash -c "/tmp/mc cp /tmp/orders_1k.json local/doris-demo/orders_1k.json" 2>&1 | tail -3

echo ""
echo "=== 7. 列出 bucket 内容 ==="
docker exec doris-minio bash -c "/tmp/mc ls local/doris-demo/" 2>&1 | tail -5

echo ""
echo "=== 8. 设置 bucket 为公开读（便于 Doris 直连测试）==="
docker exec doris-minio bash -c "/tmp/mc anonymous set download local/doris-demo" 2>&1 | tail -3

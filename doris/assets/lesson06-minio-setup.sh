#!/bin/bash
set -x
echo "=== 启动 MinIO（S3 兼容对象存储）==="
docker rm -f doris-minio 2>/dev/null
docker run -d --name doris-minio \
  --network doris-net \
  --hostname minio \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio:RELEASE.2023-03-20T20-16-18Z \
  server /data --console-address ":9001"

echo ""
echo "=== 等 15 秒 ==="
sleep 15

echo ""
echo "=== 容器状态 ==="
docker ps --filter name=doris-minio --format '{{.Names}}|{{.Status}}'

echo ""
echo "=== 从 doris-learn 测试连通 ==="
docker exec doris-learn bash -c "timeout 8 bash -c '</dev/tcp/minio/9000' && echo 'CONNECT_OK' || echo 'CONNECT_FAIL'"

echo ""
echo "=== 检查 mc 客户端是否存在 ==="
docker exec doris-learn bash -c "which mc aws 2>/dev/null; ls /opt/apache-doris/ 2>/dev/null"

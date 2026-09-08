#!/usr/bin/env bash
# 课 9 实验环境：长期存储选型
# 覆盖 Thanos（sidecar + querier + store-gateway + MinIO）、Mimir（单体模式）、
# VictoriaMetrics（单节点 + 最小集群），以及 remote read 三种模式对比。
set -euo pipefail

NET=l9net
LAB=D:/projects/learning/prometheus/labs/lesson-09

echo "=== 0. 清理旧环境 ==="
docker rm -f l9-minio l9-thanos-store l9-thanos-query l9-thanos-compact \
  l9-prom-1 l9-prom-2 l9-thanos-sc-1 l9-thanos-sc-2 \
  l9-mimir l9-vm-single \
  l9-vmstorage l9-vminsert l9-vmselect l9-vmcluster \
  l9-app l9-otelcol l9-prom-otlp 2>/dev/null || true
docker network rm $NET 2>/dev/null || true

echo "=== 1. 建网 ==="
docker network create $NET >/dev/null
echo "network $NET created"

echo "=== 2. MinIO（对象存储，Thanos / Mimir 共用）==="
docker run -d --name l9-minio --network $NET \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio:RELEASE.2023-03-20T20-16-18Z \
  server /data --console-address ":9001" >/dev/null
echo "minio started"

# 等 MinIO 就绪
for i in $(seq 1 40); do
  if docker run --rm --network $NET curlimages/curl:latest \
      -s -o /dev/null -w '%{http_code}' http://l9-minio:9000/minio/health/live \
      2>/dev/null | grep -q 200; then
    echo "minio ready after ${i}s"; break
  fi
  sleep 1
done

echo "=== 3. 建 bucket ==="
docker run --rm --network $NET \
  -e MC_HOST_l9=http://minioadmin:minioadmin@l9-minio:9000 \
  --entrypoint sh minio/mc:latest -c "
set -e
mc mb --ignore-existing l9/thanos >/dev/null 2>&1 && echo 'bucket thanos ready'
mc mb --ignore-existing l9/mimir  >/dev/null 2>&1 && echo 'bucket mimir ready'
mc ls l9/
" 2>&1 | grep -v '^$' || true

echo "=== 4. 被测应用 ==="
docker build -t l9-app:latest "$LAB/app" >/dev/null 2>&1 && echo "l9-app image built"
docker run -d --name l9-app --network $NET l9-app:latest >/dev/null
echo "app started"

echo "=== SETUP DONE ==="
docker ps --format '{{.Names}}\t{{.Status}}' | grep '^l9-' || true

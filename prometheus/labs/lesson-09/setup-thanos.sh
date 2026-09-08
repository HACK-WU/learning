#!/usr/bin/env bash
# Thanos 最小可运行拓扑（v0.42.4）
# 修正点：
#   1. S3 字段 s3forcepathstyle -> force_s3_path_style（旧字段会直接启动失败）
#   2. query 的 --store 已移除 -> 用 --store.sd-files 服务发现
#   3. Prometheus 与 sidecar 共享同一个 named volume，sidecar 才能读到 TSDB
set -euo pipefail

NET=l9net
LAB=/mnt/d/projects/learning/prometheus/labs/lesson-09
IMG=quay.io/thanos/thanos:v0.42.4

docker rm -f l9-prom-1 l9-prom-2 l9-thanos-sc-1 l9-thanos-sc-2 \
  l9-thanos-store l9-thanos-query 2>/dev/null || true
docker volume rm l9data1 l9data2 2>/dev/null || true

echo "=== 1. Prometheus 双副本（cluster 相同、replica 不同）==="
for i in 1 2; do
  docker volume create l9data$i >/dev/null
  docker run -d --name l9-prom-$i --network $NET \
    -v $LAB/prom-thanos-$i.yml:/etc/prometheus/prometheus.yml:ro \
    -v l9data$i:/prometheus \
    prom/prometheus:v3.14.0 \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --storage.tsdb.min-block-duration=2h \
    --storage.tsdb.max-block-duration=2h \
    --storage.tsdb.retention.time=6h \
    --web.enable-lifecycle \
    --web.enable-admin-api >/dev/null
  echo "l9-prom-$i started"
done

echo "=== 2. Sidecar（挂载同一个 volume 读 TSDB）==="
for i in 1 2; do
  docker run -d --name l9-thanos-sc-$i --network $NET \
    -v $LAB/thanos-bucket.yml:/etc/thanos/bucket.yml:ro \
    -v l9data$i:/prometheus \
    $IMG sidecar \
    --tsdb.path=/prometheus \
    --prometheus.url=http://l9-prom-$i:9090 \
    --objstore.config-file=/etc/thanos/bucket.yml \
    --http-address=0.0.0.0:19191 \
    --grpc-address=0.0.0.0:19090 >/dev/null
  echo "l9-thanos-sc-$i started"
done

echo "=== 3. Store Gateway ==="
docker run -d --name l9-thanos-store --network $NET \
  -v $LAB/thanos-bucket.yml:/etc/thanos/bucket.yml:ro \
  $IMG store \
  --objstore.config-file=/etc/thanos/bucket.yml \
  --data-dir=/tmp/thanos-store \
  --http-address=0.0.0.0:19191 \
  --grpc-address=0.0.0.0:19090 >/dev/null
echo "l9-thanos-store started"

echo "=== 4. Querier ==="
docker run -d --name l9-thanos-query --network $NET \
  -p 19400:19191 \
  -v $LAB/sd-files:/etc/thanos/sd:ro \
  $IMG query \
  --http-address=0.0.0.0:19191 \
  --grpc-address=0.0.0.0:19090 \
  --query.replica-label=replica \
  --store.sd-files=/etc/thanos/sd/stores.yaml \
  --store.sd-interval=10s >/dev/null
echo "l9-thanos-query started (host :19400)"

echo "=== 5. 等待就绪 ==="
sleep 18
for c in l9-prom-1 l9-prom-2 l9-thanos-sc-1 l9-thanos-sc-2 l9-thanos-store l9-thanos-query; do
  state=$(docker inspect -f '{{.State.Status}}' $c 2>/dev/null || echo missing)
  echo "$c: $state"
done

echo "=== 6. Querier 发现的 store ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-thanos-query:19191/api/v1/stores 2>/dev/null | head -c 800
echo
echo "=== DONE ==="

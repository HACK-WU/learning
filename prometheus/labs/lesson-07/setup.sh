#!/usr/bin/env bash
set -u
L7="$(pwd)/labs/lesson-07"
NET=l7net

docker network create $NET 2>/dev/null || true

echo "=== 构建镜像 ==="
docker build -q -t l7-app:latest -f "$L7/app/Dockerfile.app" "$L7/app"
docker build -q -t l7-receiver:latest -f "$L7/app/Dockerfile" "$L7/app"
echo "build done"

echo "=== 清理旧容器 ==="
for c in l7-prom l7-agent l7-app l7-receiver l7-backend l7-vm; do
  docker rm -f $c >/dev/null 2>&1 || true
done

echo "=== 启动数据源 ==="
docker run -d --name l7-app --network $NET l7-app:latest >/dev/null
echo "l7-app up"

echo "=== 启动可控 receiver ==="
docker run -d --name l7-receiver --network $NET -p 19099:8080 l7-receiver:latest >/dev/null
echo "l7-receiver up (ctrl: http://localhost:19099/stats)"

echo "=== 启动主 Prometheus（server 模式，remote_write 到 receiver） ==="
docker run -d --name l7-prom --network $NET -p 19100:9090 \
  -v "$L7/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null
echo "l7-prom up (http://localhost:19100)"

echo "=== 启动 VictoriaMetrics 作为真实后端（remote read 用） ==="
docker run -d --name l7-vm --network $NET -p 19101:8428 \
  victoriametrics/victoria-metrics:v1.151.0 \
  --storageDataPath=/vmdata \
  --retentionPeriod=30d \
  --httpListenAddr=:8428 >/dev/null
echo "l7-vm up (http://localhost:19101)"

echo "=== 等待就绪 ==="
sleep 12
for c in l7-app l7-receiver l7-prom l7-vm; do
  st=$(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)
  echo "$c: $st"
done

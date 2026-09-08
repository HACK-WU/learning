#!/usr/bin/env bash
# 起两个 Prometheus，分别以 tenantA / tenantB 身份 remote write 到同一个 Mimir
set -euo pipefail
NET=l9net
LAB=/mnt/d/projects/learning/prometheus/labs/lesson-09

for t in a b; do
  U=$(echo $t | tr 'a-z' 'A-Z')
  docker rm -f l9-prom-mimir-$t 2>/dev/null || true
  docker run -d --name l9-prom-mimir-$t --network $NET \
    -v $LAB/prom-mimir-$t.yml:/etc/prometheus/prometheus.yml:ro \
    prom/prometheus:v3.14.0 \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --storage.tsdb.retention.time=2h \
    --web.enable-lifecycle >/dev/null
  echo "l9-prom-mimir-$t started (tenant tenant$U)"
done

echo "等待抓取与远端写入..."
sleep 25
echo "=== 容器状态 ==="
docker ps --format '{{.Names}}\t{{.Status}}' | grep 'l9-prom-mimir'

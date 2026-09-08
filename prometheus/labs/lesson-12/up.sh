#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net

cat > $D/cfg/prometheus-l12.yml <<'YML'
global:
  scrape_interval: 5s
  scrape_timeout: 4s
  evaluation_interval: 5s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: app
    static_configs:
      - targets: ["l12-app:8000"]
YML

docker rm -f l12-prom l12-app 2>/dev/null || true
docker run -d --name l12-app --network $NET -e N_SERIES=20000 -e BASE_NAME=l12_series l12-app
docker run -d --name l12-prom --network $NET \
  -v $D/cfg:/cfg:ro -v $D/data:/prometheus \
  -p 19500:9090 \
  prom/prometheus:v3.14.0 \
  --config.file=/cfg/prometheus-l12.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-admin-api \
  --web.enable-lifecycle

echo "waiting for prometheus..."
for i in $(seq 1 40); do
  if curl -sf http://localhost:19500/-/ready >/dev/null 2>&1; then echo "ready after ${i}s"; break; fi
  sleep 1
done
curl -s http://localhost:19500/-/ready; echo
echo "--- head series ---"
curl -s "http://localhost:19500/api/v1/query?query=prometheus_tsdb_head_series" | head -c 300; echo

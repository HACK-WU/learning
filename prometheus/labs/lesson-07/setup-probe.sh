#!/usr/bin/env bash
set -u
NET=l7net
docker network create $NET 2>/dev/null || true

# 1. 接收端 Prometheus（当 remote write 后端）
docker rm -f l7-backend 2>/dev/null >/dev/null || true
docker run -d --name l7-backend --network $NET \
  -p 19097:9090 \
  -v "$(pwd)/labs/lesson-07/backend.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --web.enable-remote-write-receiver >/dev/null

echo "backend started"

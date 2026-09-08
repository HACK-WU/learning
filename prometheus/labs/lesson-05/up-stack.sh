#!/bin/bash
NET=lesson05-net
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-05

docker rm -f l5-am l5-receiver l5-prom 2>/dev/null

echo "--- start receiver ---"
docker run -d --name l5-receiver --network $NET \
  -v $BASE/app:/app -v $BASE/logs:/logs \
  python:3.12-slim python3 /app/receiver.py

echo "--- start alertmanager (host 19093) ---"
docker run -d --name l5-am --network $NET \
  -v $BASE/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  -p 19093:9093 \
  prom/alertmanager:v0.30.0 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/alertmanager \
  --log.level=info

echo "--- start prometheus (host 19090) ---"
docker run -d --name l5-prom --network $NET \
  -v $BASE/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v $BASE/rules.yml:/etc/prometheus/rules.yml \
  -p 19090:9090 \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle \
  --log.level=info

sleep 8
echo "--- container status ---"
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep l5-

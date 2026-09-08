#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net
PORT=${PORT:-19440}
NAME=${NAME:-l10-prom}

docker network create $NET 2>/dev/null || true
docker rm -f $NAME 2>/dev/null || true
docker run -d --name $NAME --network $NET -p $PORT:9090 \
  -v $D/prometheus-base.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle \
  --web.enable-admin-api
echo "started $NAME on $PORT"
for i in $(seq 1 40); do
  if curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1; then echo "ready after ${i}s"; exit 0; fi
  sleep 1
done
echo "NOT READY"; docker logs $NAME 2>&1 | tail -10; exit 1

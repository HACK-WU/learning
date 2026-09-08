#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PORT=19440

docker network create $NET 2>/dev/null || true
docker rm -f l10-prom >/dev/null 2>&1
docker rm -f VWYPGWU-PC5 >/dev/null 2>&1
sleep 1
docker run -d -p 19440:9090 -v $D/prometheus-base.yml:/etc/prometheus/prometheus.yml:ro prom/prometheus:v3.14.0 --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --web.enable-lifecycle --web.enable-admin-api > /tmp/l10id.txt
CID=$(cat /tmp/l10id.txt)
echo "created: $CID"
docker rename $CID l10-prom
docker network connect $NET l10-prom
echo "=== result ==="
docker ps --filter name=l10-prom --format '{{.Names}}|{{.Status}}|{{.Ports}}'
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1; then echo "ready"; exit 0; fi
  sleep 1
done
echo "not ready"; docker logs l10-prom 2>&1 | tail -5

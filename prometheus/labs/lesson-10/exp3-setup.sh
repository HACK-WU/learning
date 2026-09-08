#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PORT=19440

docker rm -f l10-prom >/dev/null 2>&1
docker rm -f l10-app >/dev/null 2>&1
# 混合场景：基线 + 直方图 + 2000 URL + 500 user + 1000 reqid
docker run -d --name l10-app --network $NET \
  -e N_USERS=500 -e N_URLS=2000 -e N_REQIDS=1000 l10-app >/dev/null 2>&1
sleep 2
docker run -d -p $PORT:9090 \
  -v $D/prometheus-base.yml:/etc/prometheus/prometheus.yml:ro \
  --name tmp-prom prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --web.enable-lifecycle --web.enable-admin-api >/dev/null 2>&1
docker rename tmp-prom l10-prom >/dev/null 2>&1
docker network connect $NET l10-prom >/dev/null 2>&1
for i in $(seq 1 30); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
sleep 22
echo "混合场景已就绪（500 user + 2000 url + 1000 reqid + 直方图）"
curl -s "http://localhost:$PORT/api/v1/status/tsdb" | python3 -c "
import sys,json;print('numSeries =',json.load(sys.stdin)['data']['headStats']['numSeries'])"

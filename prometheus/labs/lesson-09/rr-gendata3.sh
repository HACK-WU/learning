#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-09
CARD=${1:-500}
echo "=== rebuild app with RR_CARD=$CARD ==="
docker build -t l9-app -f $D/app/Dockerfile $D/app 2>&1 | tail -3
docker rm -f l9-app 2>/dev/null || true
NET=$(docker inspect l9-prom-1 --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
docker run -d --name l9-app --network $NET -e RR_CARD=$CARD l9-app
echo "=== wait for scrape ==="
sleep 20
docker exec l9-prom-1 wget -q -O - 'http://localhost:9090/api/v1/query?query=count(rr_bench)' 2>&1 | head -c 200
echo ""

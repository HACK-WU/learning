#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-09
cp $D/rr_client.py $D/app/rr_client.py
NET=$(docker inspect l9-prom-1 --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
echo "network=$NET"
docker build -t l9-rrclient -f $D/app/Dockerfile.rrclient $D/app 2>&1 | tail -5
docker rm -f l9-rrclient 2>/dev/null || true
docker run -d --name l9-rrclient --network $NET l9-rrclient
echo "=== client started ==="
docker exec l9-rrclient python -c "import cramjam; print('cramjam ok')"

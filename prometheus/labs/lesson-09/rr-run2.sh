#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-09
cp $D/rr_client.py $D/app/rr_client.py
docker build -t l9-rrclient -f $D/app/Dockerfile.rrclient $D/app 2>&1 | tail -2
docker rm -f l9-rrclient 2>/dev/null || true
NET=$(docker inspect l9-prom-1 --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
docker run -d --name l9-rrclient --network $NET l9-rrclient >/dev/null
echo "=== run: target=$1 metric=$2 dur=$3 ==="
docker exec l9-rrclient python /rr_client.py "$2" "$3" 9090 "$1" 2>&1

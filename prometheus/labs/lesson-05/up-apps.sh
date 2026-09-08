#!/bin/bash
NET=lesson05-net
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-05

docker network create $NET 2>/dev/null
docker rm -f l5-app-1 l5-app-2 l5-app-3 2>/dev/null

run_app () {
  docker run -d --name "$1" --network $NET \
    -v $BASE/app:/app \
    -e APP_INSTANCE="$1" -e APP_TEAM="$2" -e APP_ZONE="$3" \
    python:3.12-slim python3 /app/l5_app.py
}

run_app l5-app-1 payments zone-a
run_app l5-app-2 payments zone-b
run_app l5-app-3 search    zone-a

sleep 4
for c in l5-app-1 l5-app-2 l5-app-3; do
  echo "== $c =="
  docker logs $c 2>&1 | tail -2
done

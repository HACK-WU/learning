#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net
mkdir -p $D/httpcfg
: > $D/httpcfg/empty.yml

echo "===== 空配置文件 + healthy ====="
docker run --rm --network $NET -v $D/httpcfg:/h --entrypoint promtool prom/prometheus:v3.14.0 \
  check healthy --http.config.file=/h/empty.yml 2>&1 | head -5
echo "exit=$?"

echo
echo "===== 空配置文件 + ready ====="
docker run --rm --network $NET -v $D/httpcfg:/h --entrypoint promtool prom/prometheus:v3.14.0 \
  check ready --http.config.file=/h/empty.yml 2>&1 | head -5
echo "exit=$?"

echo
echo "===== 关键对照：query series / query instant 都接受 server ====="
docker run --rm --network $NET --entrypoint promtool prom/prometheus:v3.14.0 \
  query series --match='up' http://l12-prom2:9090 2>&1 | head -3

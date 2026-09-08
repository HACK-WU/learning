#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net

echo "===== 先查证这个 flag 在 3.14.0 是否存在 ====="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep -i "max-series\|max_samples\|head-series" || echo "(未匹配到)"

echo
echo "===== 用 --storage.tsdb.max-series-per-* 启动 ====="
docker rm -f l12-lim 2>/dev/null || true
mkdir -p $D/data-lim
docker run -d --name l12-lim --network $NET \
  -e N_SERIES=50000 \
  -v $D/cfg:/cfg:ro -v $D/data-lim:/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/cfg/prometheus-l12.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.max-series-per-metric=1000 \
  --storage.tsdb.max-series-per-label-set=1000 \
  --storage.tsdb.head-series-limit=5000 2>&1 | tail -3

sleep 3
echo "--- 启动结果 ---"
if docker ps --filter name=l12-lim --format '{{.Names}} {{.Status}}' | grep -q l12-lim; then
  echo "容器仍在运行"
  docker logs l12-lim 2>&1 | grep -i "error\|invalid\|unknown" | head -10
else
  echo "容器已退出（flag 不被接受 → 启动失败）"
  docker logs l12-lim 2>&1 | tail -10
fi

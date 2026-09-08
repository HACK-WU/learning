#!/usr/bin/env bash
# Mimir 单体模式（-target=all）：最小可运行，用于验证多租户与 HA tracker
set -euo pipefail
NET=l9net
LAB=/mnt/d/projects/learning/prometheus/labs/lesson-09

docker rm -f l9-mimir 2>/dev/null || true

echo "=== 启动 Mimir（单体模式，多租户开启）==="
docker run -d --name l9-mimir --network $NET \
  -p 19410:8080 \
  -v $LAB/mimir-config.yml:/etc/mimir/mimir-config.yml:ro \
  grafana/mimir:3.2.0 \
  -config.file=/etc/mimir/mimir-config.yml \
  -target=all >/dev/null
echo "l9-mimir started (host :19410)"

echo "等待就绪..."
for i in $(seq 1 40); do
  code=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' \
    http://l9-mimir:8080/ready 2>/dev/null || echo 000)
  if [ "$code" = "200" ]; then echo "mimir ready after ${i}s"; break; fi
  sleep 2
done
echo "ready code: $code"

echo "=== 状态 ==="
docker inspect -f '{{.State.Status}}' l9-mimir
echo "=== 最近日志 ==="
docker logs l9-mimir 2>&1 | tail -12

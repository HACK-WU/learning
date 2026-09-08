#!/usr/bin/env bash
set -u
L7="$(pwd)/labs/lesson-07"

echo "=== 重建 backend（带 l7-app 抓取任务） ==="
docker rm -f l7-backend >/dev/null 2>&1 || true
docker run -d --name l7-backend --network l7net -p 19105:9090 \
  -v "$L7/backend-app.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.enable-remote-write-receiver \
  --web.enable-lifecycle >/dev/null
echo "l7-backend 已重建"

sleep 25

echo
echo "=== backend 里有数据吗 ==="
docker exec l7-backend wget -qO- --timeout=10 \
  'http://localhost:9090/api/v1/query?query=count%28l7_card_balance%29' 2>/dev/null | head -c 250
echo
echo
echo "=== 经宿主机端口 19105 查 ==="
curl -s --max-time 10 --data-urlencode 'query=count(l7_card_balance)' \
  http://localhost:19105/api/v1/query 2>/dev/null | head -c 250
echo

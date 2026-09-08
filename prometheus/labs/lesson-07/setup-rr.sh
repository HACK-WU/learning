#!/usr/bin/env bash
set -u
L7="$(pwd)/labs/lesson-07"
NET=l7net

echo "=== 校验两份 remote_read 配置 ==="
for f in prometheus-rr.yml prometheus-rr-only.yml; do
  echo "--- $f ---"
  docker run --rm -v "$L7/$f:/tmp/c.yml:ro" \
    --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
    check config /tmp/c.yml 2>&1 | tail -n 3
done

echo
echo "=== 启动带 remote_read 的 Prometheus（读写到 VM） ==="
docker rm -f l7-prom-rr >/dev/null 2>&1 || true
docker run -d --name l7-prom-rr --network $NET -p 19102:9090 \
  -v "$L7/prometheus-rr.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15m \
  --web.enable-lifecycle >/dev/null
echo "l7-prom-rr up (http://localhost:19102)"

echo
echo "=== 启动只读实例（不写远端，仅 remote read） ==="
docker rm -f l7-prom-ro >/dev/null 2>&1 || true
docker run -d --name l7-prom-ro --network $NET -p 19103:9090 \
  -v "$L7/prometheus-rr-only.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15m \
  --web.enable-lifecycle >/dev/null
echo "l7-prom-ro up (http://localhost:19103)"

echo
echo "=== 等待就绪 ==="
sleep 15
for c in l7-prom-rr l7-prom-ro l7-vm; do
  echo "$c: $(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)"
done

echo
echo "=== VM 里有数据吗 ==="
docker exec l7-vm wget -qO- 'http://localhost:8428/api/v1/query?query=count(l7_card_balance)' 2>/dev/null \
  | head -c 300
echo

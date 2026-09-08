#!/usr/bin/env bash
set -u
L7="$(pwd)/labs/lesson-07"
NET=l7net

echo "=== 启动后端 Prometheus（开启 remote write receiver，天然支持 remote read） ==="
docker rm -f l7-backend >/dev/null 2>&1 || true
docker run -d --name l7-backend --network $NET -p 19105:9090 \
  -v "$L7/backend.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.enable-remote-write-receiver \
  --web.enable-lifecycle >/dev/null
echo "l7-backend up (http://localhost:19105)"

sleep 12

echo
echo "=== 校验 remote read 配置 ==="
for f in prom-reader.yml; do
  docker run --rm -v "$L7/$f:/tmp/c.yml:ro" \
    --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
    check config /tmp/c.yml 2>&1 | tail -n 3
done

echo
echo "=== 启动 reader（只 remote read，本地 retention 极短） ==="
docker rm -f l7-reader >/dev/null 2>&1 || true
docker run -d --name l7-reader --network $NET -p 19106:9090 \
  -v "$L7/prom-reader.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=10m \
  --web.enable-lifecycle >/dev/null
echo "l7-reader up (http://localhost:19106)"

sleep 15

echo
echo "=== 让 writer 把数据写进 backend ==="
echo "    l7-prom-rr 已配置 remote_write 到 l7-vm，需改为写 backend"
echo "    这里直接让 backend 自己抓 l7-app（backend.yml 只抓了自己）"
echo "    改用：给 backend 加一个抓取 l7-app 的 job"

cat > "$L7/backend-app.yml" <<'EOF'
global:
  scrape_interval: 2s
  external_labels:
    cluster: l7-backend
    role: longterm

scrape_configs:
  - job_name: l7-app-from-backend
    static_configs:
      - targets: ["l7-app:8080"]
  - job_name: backend-self
    static_configs:
      - targets: ["localhost:9090"]
EOF

docker cp "$L7/backend-app.yml" l7-backend:/etc/prometheus/prometheus.yml
docker exec l7-backend wget -qO- --post-data="" http://localhost:9090/-/reload
echo "    backend 已重载，开始抓 l7-app"

sleep 20

echo
echo "=== 确认状态 ==="
for c in l7-backend l7-reader; do
  echo "  $c: $(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)"
done

echo
echo "=== backend 里有 l7_card_balance 吗 ==="
docker exec l7-backend wget -qO- --timeout=10 \
  'http://localhost:9090/api/v1/query?query=count%28l7_card_balance%29' 2>/dev/null | head -c 200
echo

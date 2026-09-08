#!/usr/bin/env bash
# 实测：--web.enable-otlp-receiver 启用后，端点是否真的能收 OTLP 数据
set -uo pipefail
NET=l9net
IMG=prom/prometheus:v3.14.0

cat > /tmp/otlp-cfg2.yml <<'EOF'
global:
  scrape_interval: 15s
otlp:
  promote_resource_attributes:
    - service.name
EOF

echo "=== 1. 用 --web.enable-otlp-receiver 启动 ==="
docker rm -f l9-prom-otlp 2>/dev/null || true
docker run -d --name l9-prom-otlp --network $NET \
  -v /tmp/otlp-cfg2.yml:/etc/prometheus/prometheus.yml:ro \
  -p 19430:9090 \
  $IMG \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-otlp-receiver >/dev/null
echo "started"

for i in $(seq 1 30); do
  code=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' \
    http://l9-prom-otlp:9090/-/ready 2>/dev/null || echo 000)
  [ "$code" = "200" ] && { echo "ready after ${i}s"; break; }
  sleep 1
done

echo
echo "=== 2. 启动日志有无报错 ==="
docker logs l9-prom-otlp 2>&1 | grep -iE 'error|otlp' | head -5 || echo "  (无 error 行)"

echo
echo "=== 3. /api/v1/features 里 otlp_receiver 的状态 ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-prom-otlp:9090/api/v1/features 2>/dev/null | head -c 400
echo

echo
echo "=== 4. 真发一个 OTLP 请求看端点是否接受 ==="
echo "  -- 用 OTel Collector 发 OTLP 给 Prometheus --"
cat > /tmp/otelcol-otlp.yml <<'EOF'
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: gen
          static_configs:
            - targets: ["l9-app:8000"]
exporters:
  otlphttp/prom:
    endpoint: http://l9-prom-otlp:9090/api/v1/otlp
    tls:
      insecure: true
service:
  pipelines:
    metrics:
      receivers: [prometheus]
      exporters: [otlphttp/prom]
EOF
docker rm -f l9-otelcol 2>/dev/null || true
docker run -d --name l9-otelcol --network $NET \
  -v /tmp/otelcol-otlp.yml:/etc/otelcol/config.yml:ro \
  otel/opentelemetry-collector-contrib:0.133.0 \
  --config /etc/otelcol/config.yml >/dev/null
echo "  otelcol started"
sleep 20

echo
echo "=== 5. Prometheus 里是否出现 OTLP 写入的指标 ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-prom-otlp:9090/api/v1/label/__name__/values 2>/dev/null | head -c 500
echo

echo
echo "=== 6. otelcol 日志（有无发送失败）==="
docker logs l9-otelcol 2>&1 | grep -iE 'error|fail' | head -5 || echo "  (无 error 行)"

#!/usr/bin/env bash
L7="$(pwd)/labs/lesson-07"

echo "=== 用 promtool 校验主配置（含 queue_config 字段名） ==="
docker run --rm \
  -v "$L7/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /etc/prometheus/prometheus.yml 2>&1 | tail -n 20

echo
echo "=== 故意写错字段名，看 promtool 是否报错（验证校验有效） ==="
cat > /tmp/bad_qc.yml <<'EOF'
global:
  scrape_interval: 5s
remote_write:
  - url: "http://example.com/api/v1/write"
    queue_config:
      capacity: 1000
      max_shardz: 10
scrape_configs:
  - job_name: x
    static_configs:
      - targets: ["localhost:9090"]
EOF
docker run --rm -v "/tmp/bad_qc.yml:/tmp/bad_qc.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /tmp/bad_qc.yml 2>&1 | tail -n 10

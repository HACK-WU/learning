#!/usr/bin/env bash
echo "=== remote_read 配置项：从 promtool 的文档/schema 侧确认 ==="
docker run --rm --entrypoint /bin/promtool prom/prometheus:v3.14.0 check config /dev/null 2>&1 | head -n 5

echo
echo "=== 用一个错误字段名探测 remote_read 支持哪些字段 ==="
cat > /tmp/rr_probe.yml <<'EOF'
global:
  scrape_interval: 5s
remote_read:
  - url: "http://example.com/api/v1/read"
    bogus_field: 1
scrape_configs:
  - job_name: x
    static_configs:
      - targets: ["localhost:9090"]
EOF
docker run --rm -v "/tmp/rr_probe.yml:/tmp/rr_probe.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /tmp/rr_probe.yml 2>&1 | tail -n 8

echo
echo "=== 逐个测试 remote_read 已知字段是否被接受 ==="
for f in required_matchers read_recent filter_external_labels; do
cat > /tmp/rr_$f.yml <<EOF
global:
  scrape_interval: 5s
remote_read:
  - url: "http://example.com/api/v1/read"
    $f: true
scrape_configs:
  - job_name: x
    static_configs:
      - targets: ["localhost:9090"]
EOF
  out=$(docker run --rm -v "/tmp/rr_$f.yml:/tmp/rr_$f.yml:ro" \
    --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
    check config /tmp/rr_$f.yml 2>&1 | tail -n 3)
  echo "--- $f ---"
  echo "$out"
done

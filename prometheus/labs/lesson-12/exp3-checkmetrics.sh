#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
mkdir -p $D/metrics

# 造一份"问题指标"样本：重复 HELP/TYPE、不一致标签、高基数
cat > $D/metrics/messy.prom <<'PROM'
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{code="200"} 1
http_requests_total{code="500"} 2
# HELP http_requests_total Total HTTP requests again (duplicate HELP)
# TYPE http_requests_total counter
# HELP rpc_duration_seconds RPC duration
# TYPE rpc_duration_seconds histogram
rpc_duration_seconds_bucket{le="0.1"} 5
rpc_duration_seconds_bucket{le="+Inf"} 7
rpc_duration_seconds_count 7
PROM

echo "===== [1] 标准 lint ====="
docker run --rm -i -v $D/metrics:/m --entrypoint promtool prom/prometheus:v3.14.0 \
  check metrics < $D/metrics/messy.prom 2>&1; echo "exit=$?"

echo
echo "===== [2] --extended（含基数分析） ====="
docker run --rm -i -v $D/metrics:/m --entrypoint promtool prom/prometheus:v3.14.0 \
  check metrics --extended < $D/metrics/messy.prom 2>&1; echo "exit=$?"

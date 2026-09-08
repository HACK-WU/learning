#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
mkdir -p $D/metrics

# 干净样本：无误，用于看 --extended 的输出
cat > $D/metrics/clean.prom <<'PROM'
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{code="200",user_id="u1"} 1
http_requests_total{code="200",user_id="u2"} 2
http_requests_total{code="500",user_id="u3"} 3
# HELP rpc_duration_seconds RPC duration
# TYPE rpc_duration_seconds histogram
rpc_duration_seconds_bucket{le="0.1"} 5
rpc_duration_seconds_bucket{le="+Inf"} 7
rpc_duration_seconds_count 7
PROM

echo "===== [1] 干净样本 标准 lint ====="
docker run --rm -i --entrypoint promtool prom/prometheus:v3.14.0 \
  check metrics < $D/metrics/clean.prom 2>&1; echo "exit=$?"

echo
echo "===== [2] 干净样本 --extended ====="
docker run --rm -i --entrypoint promtool prom/prometheus:v3.14.0 \
  check metrics --extended < $D/metrics/clean.prom 2>&1; echo "exit=$?"

echo
echo "===== [3] 直接对运行中 Prometheus 自身指标做 --extended ====="
curl -s http://localhost:19500/metrics > $D/metrics/self.prom
wc -l < $D/metrics/self.prom
docker run --rm -i --entrypoint promtool prom/prometheus:v3.14.0 \
  check metrics --extended < $D/metrics/self.prom 2>&1 | head -40; echo "exit=$?"

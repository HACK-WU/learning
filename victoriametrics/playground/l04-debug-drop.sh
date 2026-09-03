#!/usr/bin/env bash
# 课 4 疑点排查：为什么 VM 侧的 prometheus_http_request_duration_seconds_* (48)
# 反而比 Prometheus 本地 (36) 更多？metric_relabel drop 到底生效没有？
set -u
VM=http://localhost:8428
PROM=http://localhost:9090
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py

echo "===== 1. 对比两侧的 job 分布 ====="
for side in VM PROM; do
  url=$(eval echo \$$side)
  echo "--- $side ---"
  curl -s -m 15 -G "$url/api/v1/query" \
    --data-urlencode 'query=count({__name__=~"prometheus_http_request_duration_seconds_.*"}) by (job)' \
    --data-urlencode "nocache=1" | python3 "$FMT"
done

echo
echo "===== 2. 关键：两个 job 都要抓 localhost:9090 ====="
echo "    prometheus            job：原始，未过滤"
echo "    prometheus-filtered   job：带 metric_relabel drop"
echo "    所以 VM 侧 = prometheus job 的完整集 + filtered job 的剩余集"

echo
echo "===== 3. 逐 job 核对（VM 侧）====="
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=count({__name__=~"prometheus_http_request_duration_seconds_.*"}) by (job)' \
  --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "===== 4. 逐 job 核对（Prometheus 本地）====="
curl -s -m 15 -G "$PROM/api/v1/query" \
  --data-urlencode 'query=count({__name__=~"prometheus_http_request_duration_seconds_.*"}) by (job)' \
| python3 "$FMT"

echo
echo "===== 5. 直接验证 drop 生效：查 filtered job 里是否还有该指标 ====="
echo "--- VM: 按 job 拆开看 series 数 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=count({__name__=~"prometheus_http_request_duration_seconds_bucket"}) by (job)' \
  --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "===== 6. 用一个干净的对照：只存在于 filtered job 的标签 source ====="
echo "--- VM: up{job=prometheus-filtered} ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=up{job="prometheus-filtered"}' \
  --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "===== 7. Prometheus 本地 filtered job 里该指标是否存在 ====="
curl -s -m 15 -G "$PROM/api/v1/query" \
  --data-urlencode 'query=count({__name__=~"prometheus_http_request_duration_seconds_bucket",job="prometheus-filtered"})' \
| python3 "$FMT"

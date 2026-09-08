#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net
P=http://localhost:19501

echo "===== [1] promtool check healthy / ready（快速定级） ====="
echo -n "healthy: "
docker run --rm --network $NET --entrypoint promtool prom/prometheus:v3.14.0 check healthy http://l12-prom2:9090 2>&1
echo -n "ready:   "
docker run --rm --network $NET --entrypoint promtool prom/prometheus:v3.14.0 check ready http://l12-prom2:9090 2>&1
echo "（注意：target down 不影响 Prometheus 自身 healthy/ready —— 说明故障在采集侧，不在存储/查询侧）"

echo
echo "===== [2] promtool query：绕过 UI 直接确认数据面 ====="
docker run --rm --network $NET --entrypoint promtool prom/prometheus:v3.14.0 \
  query instant http://l12-prom2:9090 'up{job="slowapp"}' 2>&1
echo "---"
docker run --rm --network $NET --entrypoint promtool prom/prometheus:v3.14.0 \
  query instant http://l12-prom2:9090 'slow_metric' 2>&1
echo "（slow_metric 为空 → 超时导致样本根本没进 TSDB，不是查询问题）"

echo
echo "===== [3] 用 promtool 直接测源站真实耗时（关键：绕过 Prometheus） ====="
echo "--- 在 promtool 容器里 curl 源站 ---"
docker run --rm --network $NET --entrypoint sh prom/prometheus:v3.14.0 -c \
  'wget -q -O /dev/null -S http://l12-slow:8000/metrics 2>&1 | head -3; \
   time wget -q -O /dev/null http://l12-slow:8000/metrics' 2>&1 | head -10

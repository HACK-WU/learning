#!/usr/bin/env bash
echo "=== 从 Prometheus 自身 /metrics 里找 remote write 相关指标名 ==="
docker exec l7-prom wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_remote" | sed 's/{.*//' | sort -u

echo
echo "=== 计数：一共多少个 remote 相关指标 ==="
docker exec l7-prom wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -cE "^prometheus_remote"

echo
echo "=== 完整前 40 行（含标签示例） ==="
docker exec l7-prom wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_remote" | head -n 40

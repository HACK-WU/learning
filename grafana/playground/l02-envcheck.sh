#!/usr/bin/env bash
# 课 2 开课前：核验实验环境状态
set -u
echo "=== A. 容器状态 ==="
docker ps -a --filter "name=grafana-" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo "=== B. 端口监听（宿主） ==="
for p in 3001 9201 9101; do
  if ss -ltn 2>/dev/null | grep -q ":$p "; then
    echo "  ✅ $p 已监听"
  else
    echo "  ❌ $p 未监听"
  fi
done

echo
echo "=== C. Grafana 健康 ==="
curl -s "http://localhost:3001/api/health" ; echo

echo
echo "=== D. Prometheus 身份校验 ==="
curl -s "http://localhost:9201/api/v1/query?query=up" | head -c 400 ; echo

echo
echo "=== E. node-exporter 身份校验 ==="
curl -s "http://localhost:9101/metrics" | grep -c '^node_cpu_seconds_total' | xargs -I{} echo "  node_cpu_seconds_total 系列数: {}"

echo
echo "=== F. Grafana 版本 ==="
curl -s "http://localhost:3001/api/health" >/dev/null && docker exec grafana-lab grafana server -v 2>/dev/null || echo "  （无法取得）"

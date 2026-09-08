#!/usr/bin/env bash
echo "=== Agent 的存储相关 flag（决定断网能扛多久） ==="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 \
  | grep -A2 -E "storage\.agent\.(retention|path|no-lockfile)" | head -n 30

echo
echo "=== Agent 实例实际使用的 flag ==="
docker exec l7-agent wget -qO- 'http://localhost:9090/api/v1/status/flags' 2>/dev/null \
  | tr ',' '\n' | grep -iE "agent|storage" | head -n 20

echo
echo "=== Agent 的 WAL 目录实际内容 ==="
docker exec l7-agent sh -c 'ls -la /data-agent/ 2>/dev/null; echo "--- wal ---"; ls -la /data-agent/wal/ 2>/dev/null | head -n 10'

echo
echo "=== Agent 的 remote write 指标（从 /metrics 直接读） ==="
docker exec l7-agent wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_remote_storage" | grep -v "_bucket" | head -n 15

echo
echo "=== 对照：Server 的 WAL ==="
docker exec l7-prom sh -c 'du -sh /prometheus/wal 2>/dev/null'
docker exec l7-agent sh -c 'du -sh /data-agent/wal 2>/dev/null'

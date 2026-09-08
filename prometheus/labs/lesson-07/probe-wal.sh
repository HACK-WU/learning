#!/usr/bin/env bash
echo "=== remote write 的 WAL 目录内容 ==="
docker exec l7-prom sh -c 'ls -la /prometheus/wal/ 2>/dev/null | head -n 20'

echo
echo "=== WAL 段数量与总大小 ==="
docker exec l7-prom sh -c 'ls -1 /prometheus/wal/ 2>/dev/null | wc -l; du -sh /prometheus/wal/ 2>/dev/null'

echo
echo "=== checkpoint 目录（remote write 有自己的 checkpoint） ==="
docker exec l7-prom sh -c 'ls -la /prometheus/ 2>/dev/null'

echo
echo "=== WAL 相关指标 ==="
docker exec l7-prom wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_tsdb_wal" | grep -v "_bucket" | head -n 20

echo
echo "=== remote write 相关的 storage flag 当前值 ==="
docker exec l7-prom sh -c 'ps aux | grep -o "\-\-storage[^ ]*" | head -n 20' 2>/dev/null

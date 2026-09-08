#!/usr/bin/env bash
echo "=== 1) TSDB WAL 截断周期由什么控制？查 retention 与 compaction ==="
docker exec l7-prom sh -c 'ps aux | head -n 3'
echo
echo "=== 2) 是否存在 remote write 专属目录（如 wal watcher checkpoint） ==="
docker exec l7-prom sh -c 'find /prometheus -maxdepth 2 -type d 2>/dev/null'
echo
echo "=== 3) 查看是否有 remote_write 相关的 out_of_order / checkpoint 文件 ==="
docker exec l7-prom sh -c 'find /prometheus -maxdepth 2 -name "*checkpoint*" -o -maxdepth 2 -name "*remote*" 2>/dev/null'
echo
echo "=== 4) 关键：TSDB WAL 保留多久？head block 多久 compaction 一次 ==="
docker exec l7-prom wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "prometheus_tsdb_head_max_time|prometheus_tsdb_head_min_time|prometheus_tsdb_retention_limit_seconds|prometheus_tsdb_wal_segment_current" 
echo
echo "=== 5) head block 的 min/max 时间跨度（WAL 覆盖了多久的数据） ==="
docker exec l7-prom wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_tsdb_head_(min|max)_time"

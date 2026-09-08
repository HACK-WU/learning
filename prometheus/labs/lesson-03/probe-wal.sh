set -x
cd /mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== wal 目录 ==="
ls -la data/wal

echo "=== chunks_head ==="
ls -la data/chunks_head

echo "=== 全库序列数 vs head 序列数 ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=prometheus_tsdb_head_series'

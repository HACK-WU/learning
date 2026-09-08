set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== 删除后 block 数量 ==="
ls "$BASE/data-compact" | wc -l

echo
echo "=== 剩余 block 清单 ==="
docker exec l3-compact /bin/promtool tsdb list /prometheus 2>&1 | head -20

echo
echo "=== 删除日志：注意是 Deleting obsolete block（整块删） ==="
docker logs l3-compact 2>&1 | grep -iE 'Deleting obsolete block|head garbage collect|retention' | head -15

echo
echo "=== 关键对比：head 里的数据还在吗？（保留不删 head） ==="
curl -s -G 'http://localhost:9098/api/v1/query' \
  --data-urlencode 'query=prometheus_tsdb_head_series'

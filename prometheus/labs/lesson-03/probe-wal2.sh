set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== 当前 WAL 目录（l3-prom 已跑一段时间） ==="
ls -la "$BASE/data/wal"

echo
echo "=== WAL 相关指标 ==="
for q in 'prometheus_tsdb_wal_segment_current' \
         'prometheus_tsdb_wal_fsync_duration_seconds_count' \
         'prometheus_tsdb_head_series' \
         'prometheus_tsdb_head_chunks'; do
  echo "--- $q ---"
  curl -s -G 'http://localhost:9097/api/v1/query' --data-urlencode "query=$q" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d['data']['result']
print('  ', r[0]['value'][1] if r else '(空)')
"
done

echo
echo "=== TSDB 总体状态（head + block） ==="
curl -s 'http://localhost:9097/api/v1/status/tsdb' | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('  headStats:', json.dumps(d.get('headStats',{}), ensure_ascii=False))
"

echo
echo "=== checkpoint 相关日志 ==="
docker logs l3-prom 2>&1 | grep -iE 'checkpoint' | head -8

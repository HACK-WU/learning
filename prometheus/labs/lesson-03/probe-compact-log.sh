set -x
echo "=== compaction 相关日志 ==="
docker logs l3-compact 2>&1 | grep -iE 'compaction|compact' | grep -v 'repair.go' | head -20

echo
echo "=== 删除相关日志 ==="
docker logs l3-compact 2>&1 | grep -iE 'delet|retention|exceed' | head -15

echo
echo "=== TSDB 状态：block 数 ==="
curl -s 'http://localhost:9098/api/v1/status/tsdb' | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('  headStats:', json.dumps(d.get('headStats',{}), ensure_ascii=False))
print('  seriesCountByMetricName:', json.dumps(d.get('seriesCountByMetricName',[])[:8], ensure_ascii=False))
print('  blocks:', len(d.get('blockStats', [])) if 'blockStats' in d else 'n/a')
"

echo
echo "=== 目录计数复核 ==="
ls /mnt/d/projects/learning/prometheus/labs/lesson-03/data-compact | wc -l

set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== 再等 90 秒观察 compaction 进展 ==="
sleep 90
echo "block 数: $(ls "$BASE/vdata-compact" | wc -l)"

cd "$BASE/vdata-compact"
python3 << 'PYEOF'
import json, os, collections
c = collections.Counter()
for d in os.listdir('.'):
    p = os.path.join(d, 'meta.json')
    if os.path.isfile(p):
        m = json.load(open(p))
        c[m['compaction']['level']] += 1
print('  level -> block 数:', dict(sorted(c.items())))
PYEOF

echo "=== 合并日志条数 ==="
docker logs l3-compact 2>&1 | grep -c 'compact blocks'
docker logs l3-compact 2>&1 | grep -E 'compact blocks' | head -3

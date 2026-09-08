set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== level 分布统计 ==="
cd "$BASE/data-compact"
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

echo
echo "=== 时间跨度对比：level1 vs level2 ==="
cd "$BASE/data-compact"
python3 << 'PYEOF'
import json, os
for lvl in (1, 2, 3):
    spans = []
    for d in os.listdir('.'):
        p = os.path.join(d, 'meta.json')
        if os.path.isfile(p):
            m = json.load(open(p))
            if m['compaction']['level'] == lvl:
                spans.append((m['maxTime'] - m['minTime']) / 1e6)
    if spans:
        print('  level=%d: %d 个 block, 平均跨度 %.1f ms' % (lvl, len(spans), sum(spans)/len(spans)))
PYEOF

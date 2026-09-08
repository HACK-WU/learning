set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== 备份真实 compaction 日志（证据） ==="
docker logs l3-compact > "$BASE/evidence-compact.log" 2>&1
wc -l "$BASE/evidence-compact.log"

echo
echo "=== 当前 block 总数 ==="
ls "$BASE/data-compact" | wc -l

echo
echo "=== 合并产物的 meta.json（level=2） ==="
cd "$BASE/data-compact"
for d in */; do
  d=${d%/}
  [ -f "$d/meta.json" ] || continue
  lvl=$(python3 -c "import json;print(json.load(open('$d/meta.json'))['compaction']['level'])" 2>/dev/null)
  if [ "$lvl" = "2" ]; then
    echo "--- $d ---"
    cat "$d/meta.json"
    echo
  fi
done | head -40

echo "=== level 分布统计 ==="
cd "$BASE/data-compact"
python3 -c "
import json, os, collections
c = collections.Counter()
for d in os.listdir('.'):
    p = os.path.join(d, 'meta.json')
    if os.path.isfile(p):
        m = json.load(open(p))
        c[m['compaction']['level']] += 1
print('  level -> block 数:', dict(sorted(c.items())))
"

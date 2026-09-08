set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=v3-net

echo "########## 步骤 5：compaction ##########"
cd "$BASE"
rm -rf "$BASE/vdata-compact" && mkdir -p "$BASE/vdata-compact"
cp -r "$BASE"/vblocks/* "$BASE/vdata-compact/"
echo "种植 block 数: $(ls "$BASE/vdata-compact" | wc -l)"

docker rm -f l3-compact >/dev/null 2>&1 || true
docker run -d --name l3-compact --network "$NET" -p 9098:9090 \
  -v "$BASE/prometheus-selfonly.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/vdata-compact":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.enable-lifecycle --web.enable-admin-api >/dev/null

sleep 30
echo "compaction 后 block 数: $(ls "$BASE/vdata-compact" | wc -l)"

echo "=== 合并日志 ==="
docker logs l3-compact 2>&1 | grep -E 'compact blocks' | head -3

echo "=== level 分布 ==="
cd "$BASE/vdata-compact"
python3 -c "
import json, os, collections
c = collections.Counter()
for d in os.listdir('.'):
    p = os.path.join(d, 'meta.json')
    if os.path.isfile(p):
        m = json.load(open(p))
        c[m['compaction']['level']] += 1
print('  level -> block 数:', dict(sorted(c.items())))"

echo "=== level=2 的 meta.json ==="
cd "$BASE/vdata-compact"
for d in */; do
  d=${d%/}
  [ -f "$d/meta.json" ] || continue
  lvl=$(python3 -c "import json;print(json.load(open('$d/meta.json'))['compaction']['level'])")
  if [ "$lvl" = "2" ]; then echo "--- $d ---"; cat "$d/meta.json"; echo; break; fi
done

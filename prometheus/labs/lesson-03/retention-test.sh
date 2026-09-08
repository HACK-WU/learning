set -e
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=lesson03-net

echo "########## 实验：保留策略的删除粒度（按 block 删，不是按序列删） ##########"

# 用带 19 个 block 的 data-compact，改成极短保留时间，观察删什么
echo "=== 1) 保留前 block 清单 ==="
docker exec l3-compact /bin/promtool tsdb list /prometheus 2>&1 | head -25

echo
echo "=== 2) 关键观察：block 的时间跨度 vs 保留边界 ==="
cd "$BASE/data-compact"
python3 << 'PYEOF'
import json, os
rows = []
for d in sorted(os.listdir('.')):
    p = os.path.join(d, 'meta.json')
    if os.path.isfile(p):
        m = json.load(open(p))
        rows.append((m['compaction']['level'], m['minTime'], m['maxTime'], d))
rows.sort()
print('  level  minTime(ms)            maxTime(ms)            block')
for lvl, mn, mx, d in rows:
    print('  %-5d  %d  %d  %s' % (lvl, mn//1_000_000, mx//1_000_000, d))
import datetime
if rows:
    lo = min(r[1] for r in rows) / 1000
    hi = max(r[2] for r in rows) / 1000
    print()
    print('  整体时间范围: %s .. %s'
          % (datetime.datetime.utcfromtimestamp(lo).isoformat(),
             datetime.datetime.utcfromtimestamp(hi).isoformat()))
PYEOF

echo
echo "=== 3) 用 retention.time=1s 重启，观察删除行为 ==="
docker rm -f l3-compact >/dev/null 2>&1 || true
docker run -d --name l3-compact --network "$NET" -p 9098:9090 \
  -v "$BASE/prometheus-selfonly.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/data-compact":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1s \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

sleep 25
echo "删除后 block 数量："
ls "$BASE/data-compact" | wc -l

echo
echo "=== 4) 删除日志（关键：删的是整个 block） ==="
docker logs l3-compact 2>&1 | grep -iE 'deleting obsolete|head garbage|retention' | head -12

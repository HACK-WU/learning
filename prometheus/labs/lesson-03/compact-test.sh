set -e
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=lesson03-net

# 把 promtool 生成的 61 个小 block 放进一个"种植"目录，
# 让 Prometheus 启动时加载它们，观察后台 compaction 如何合并
rm -rf "$BASE/data-compact"
mkdir -p "$BASE/data-compact"
cp -r "$BASE"/blocks/* "$BASE/data-compact/"

echo "=== 种植前：block 数量 ==="
ls "$BASE/data-compact" | wc -l

docker rm -f l3-compact >/dev/null 2>&1 || true
docker run -d --name l3-compact --network "$NET" -p 9098:9090 \
  -v "$BASE/prometheus-selfonly.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/data-compact":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

echo "Prometheus 已启动，等待 compaction 生效（30 秒）"
sleep 30

echo
echo "=== 种植后：block 数量 ==="
ls "$BASE/data-compact" | wc -l

echo
echo "=== 现存 block 列表（promtool tsdb list） ==="
docker exec l3-compact /bin/promtool tsdb list /prometheus 2>&1 | head -20

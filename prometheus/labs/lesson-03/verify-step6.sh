set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=v3-net

echo "########## 步骤 6：保留的删除粒度 ##########"
cd "$BASE"
rm -rf "$BASE/vdata-ret" && mkdir -p "$BASE/vdata-ret"
cp -r "$BASE"/vblocks/* "$BASE/vdata-ret/"
echo "种植 block 数: $(ls "$BASE/vdata-ret" | wc -l)"

docker rm -f l3-ret >/dev/null 2>&1 || true
docker run -d --name l3-ret --network "$NET" -p 9098:9090 \
  -v "$BASE/prometheus-selfonly.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/vdata-ret":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle --web.enable-admin-api >/dev/null

sleep 30
echo "保留后 block 数: $(ls "$BASE/vdata-ret" | wc -l)"

echo "=== 删除日志（应全是整块删） ==="
docker logs l3-ret 2>&1 | grep -E 'Deleting obsolete block' | head -3
echo "=== retention 生效值 ==="
docker logs l3-ret 2>&1 | grep -E 'retention updated'

set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=lesson03-net

# 重新种植一份干净的 61 个 block
rm -rf "$BASE/data-ret"
mkdir -p "$BASE/data-ret"
cp -r "$BASE"/blocks/* "$BASE/data-ret/"
echo "种植 block 数: $(ls "$BASE/data-ret" | wc -l)"

# 用 2h 保留（低于此值 Prometheus 不接受）
docker rm -f l3-ret >/dev/null 2>&1 || true
docker run -d --name l3-ret --network "$NET" -p 9098:9090 \
  -v "$BASE/prometheus-selfonly.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/data-ret":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

echo "等待 25 秒"
sleep 25

echo "=== 保留后 block 数量 ==="
ls "$BASE/data-ret" | wc -l

echo
echo "=== 日志：retention 生效值 + 删除动作 ==="
docker logs l3-ret 2>&1 | grep -iE 'retention updated|Deleting obsolete block|head garbage' | head -10

set -e
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=lesson03-net

docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"

for c in l3-app l3-prom; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

# 干净数据目录
rm -rf "$BASE/data"
mkdir -p "$BASE/data"

docker run -d --name l3-app --network "$NET" \
  -v "$BASE/app":/app -w /app \
  python:3.12-slim python multi_app.py >/dev/null

docker run -d --name l3-prom --network "$NET" -p 9097:9090 \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/data":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

echo "等待 10 秒让首轮抓取完成"
sleep 10
docker ps --filter name=l3 --format '{{.Names}}\t{{.Status}}'

echo
echo "=== 数据目录 ==="
ls -la "$BASE/data"

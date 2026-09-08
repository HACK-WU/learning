set -e
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-04
NET=lesson04-net

docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"

for c in l4-app l4-prom; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

rm -rf "$BASE/data"
mkdir -p "$BASE/data"

echo "=== 1) 校验规则文件语法 ==="
docker run --rm -v "$BASE/rules.yml":/etc/prometheus/rules.yml \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check rules /etc/prometheus/rules.yml

echo
echo "=== 2) 校验主配置 ==="
docker run --rm \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/rules.yml":/etc/prometheus/rules.yml \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /etc/prometheus/prometheus.yml

echo
echo "=== 3) 启动应用 ==="
docker run -d --name l4-app --network "$NET" \
  -v "$BASE/app":/app -w /app \
  python:3.12-slim python fault_app.py >/dev/null

echo "=== 4) 启动 Prometheus（宿主 9094） ==="
docker run -d --name l4-prom --network "$NET" -p 9094:9090 \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/rules.yml":/etc/prometheus/rules.yml \
  -v "$BASE/data":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

echo "等待 20 秒让首轮抓取与规则求值完成"
sleep 20
docker ps --filter name=l4 --format '{{.Names}}\t{{.Status}}'

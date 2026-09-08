set -e
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-02
NET=lesson01-net

# 复用课 1 已存在的网络；不存在则创建
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"

# 清理上一轮（幂等）
for c in app-order-1 app-order-2 app-payment-1 app-user-1 app-conflict prometheus-l2; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

run_app() {
  name="$1"; app="$2"; env="$3"; fake="$4"
  docker run -d --name "$name" --network "$NET" \
    -e APP_NAME="$app" -e ENV_NAME="$env" -e FAKE_LABELS="$fake" \
    -e VERSION="1.2.3" -e REGION="cn-south" \
    -v "$BASE/app":/app -w /app \
    python:3.12-slim python multi_app.py >/dev/null
  echo "  started $name (app=$app env=$env fake_labels=$fake)"
}

run_app app-order-1   order   prod    0
run_app app-order-2   order   prod    0
run_app app-payment-1 payment prod    0
run_app app-user-1    user    staging 0
run_app app-conflict  conflict prod   1

docker run -d --name prometheus-l2 --network "$NET" -p 9096:9090 \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/sd":/etc/prometheus/sd \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle >/dev/null
echo "  started prometheus-l2 (宿主 9096 -> 容器 9090)"

echo "等待 12 秒让首轮抓取完成"
sleep 12
docker ps --filter name=app- --filter name=prometheus-l2 --format '{{.Names}}\t{{.Status}}'

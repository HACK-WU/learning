set -x

NET=lesson02-net
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"

for c in v-order-1 v-order-2 v-payment-1 v-user-1 v-conflict v-prom; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

run_app() {
  name="$1"; app="$2"; env="$3"; fake="$4"
  docker run -d --name "$name" --network "$NET" \
    -e APP_NAME="$app" -e ENV_NAME="$env" -e FAKE_LABELS="$fake" \
    -e VERSION="1.2.3" -e REGION="cn-south" \
    -v /mnt/d/projects/learning/prometheus/labs/lesson-02/app:/app -w /app \
    python:3.12-slim python multi_app.py >/dev/null
}

run_app v-order-1   order   prod    0
run_app v-order-2   order   prod    0
run_app v-payment-1 payment prod    0
run_app v-user-1    user    staging 0
run_app v-conflict  conflict prod   1

docker run -d --name v-prom --network "$NET" -p 9097:9090 \
  -v /mnt/d/projects/learning/prometheus/labs/lesson-02/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v /mnt/d/projects/learning/prometheus/labs/lesson-02/sd:/etc/prometheus/sd \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle

echo "等待 12 秒"
sleep 12
docker ps --filter name=v- --format '{{.Names}}\t{{.Status}}'

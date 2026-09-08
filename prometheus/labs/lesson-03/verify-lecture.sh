set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=v3-net

echo "########## 用讲义容器名 + 干净目录逐字验证 ##########"
for c in l3-app l3-prom l3-compact l3-ret; do docker rm -f "$c" >/dev/null 2>&1 || true; done
docker network rm "$NET" >/dev/null 2>&1 || true
docker network create "$NET"

rm -rf "$BASE/vdata" "$BASE/vdata-compact" "$BASE/vdata-ret"
mkdir -p "$BASE/vdata"

docker run -d --name l3-app --network "$NET" \
  -v "$BASE/app":/app -w /app \
  python:3.12-slim python multi_app.py >/dev/null

docker run -d --name l3-prom --network "$NET" -p 9097:9090 \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/vdata":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

sleep 15
echo "=== 步骤2：序列数换算 ==="
for m in app_requests_total app_build_info app_debug_user_id; do
  echo -n "$m: "
  curl -s -G 'http://localhost:9097/api/v1/query' --data-urlencode "query=count($m)" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['result'][0]['value'][1])"
done
echo -n "业务合计: "
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=count({__name__=~"app_.*"})' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['result'][0]['value'][1])"
echo -n "全库: "
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=count({__name__=~".+"})' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['result'][0]['value'][1])"

echo
echo "=== head_series ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=prometheus_tsdb_head_series' \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; print('  ', r[0]['value'][1] if r else '(空)')"

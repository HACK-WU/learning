set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=v3-net

echo "########## 步骤 3：WAL 与崩溃恢复 ##########"
echo "=== WAL 目录 ==="
ls -la "$BASE/vdata/wal"

echo "=== 崩溃前的值 ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_requests_total{route="/health",status="200"}'

echo "=== 硬杀 ==="
docker kill -s KILL l3-prom

echo "=== 重启 ==="
docker rm -f l3-prom >/dev/null 2>&1
docker run -d --name l3-prom --network "$NET" -p 9097:9090 \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/vdata":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-lifecycle --web.enable-admin-api >/dev/null

sleep 20
echo "=== 重启后的值 ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_requests_total{route="/health",status="200"}'

echo "=== WAL 重放日志 ==="
docker logs l3-prom 2>&1 | grep -iE 'Replaying|WAL segment loaded|WAL replay completed'

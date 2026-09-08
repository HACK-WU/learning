set -e
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=lesson03-net

echo "########## 实验：WAL checkpoint + 崩溃恢复 ##########"

# 用课3主实例 l3-prom（数据目录 data/），先跑够时间产生多个 WAL 段
echo "=== 1) 重启 l3-prom 加载新配置（含自抓取） ==="
docker rm -f l3-prom >/dev/null 2>&1 || true
docker run -d --name l3-prom --network "$NET" -p 9097:9090 \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/data":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

sleep 15
echo "当前 WAL 目录："
ls -la "$BASE/data/wal"

echo
echo "=== 2) 记录崩溃前的数据点 ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_requests_total{route="/health",status="200"}' \
  > "$BASE/before-crash.json"
python3 -c "
import json
d=json.load(open('$BASE/before-crash.json'))
print('  崩溃前最新值:', d['data']['result'][0]['value'] if d['data']['result'] else '(空)')
"

echo
echo "=== 3) 模拟崩溃：docker kill -9（不发 SIGTERM，不做优雅退出） ==="
docker kill -s KILL l3-prom

echo "崩溃后 WAL 目录（数据还在磁盘上）："
ls -la "$BASE/data/wal"

echo
echo "=== 4) 重启（触发 WAL 重放） ==="
docker rm -f l3-prom >/dev/null 2>&1 || true
docker run -d --name l3-prom --network "$NET" -p 9097:9090 \
  -v "$BASE/prometheus.yml":/etc/prometheus/prometheus.yml \
  -v "$BASE/data":/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-lifecycle \
  --web.enable-admin-api >/dev/null

sleep 20
echo
echo "=== 5) 崩溃前的样本是否还在？ ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_requests_total{route="/health",status="200"}' \
  > "$BASE/after-crash.json"
python3 -c "
import json
before=json.load(open('$BASE/before-crash.json'))['data']['result']
after=json.load(open('$BASE/after-crash.json'))['data']['result']
print('  崩溃前:', before[0]['value'] if before else '(空)')
print('  重启后:', after[0]['value'] if after else '(空)')
"

echo
echo "=== 6) 重启日志里的 WAL 重放痕迹 ==="
docker logs l3-prom 2>&1 | grep -iE 'replay|wal|head|checkpoint' | head -12

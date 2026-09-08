set -e

echo "=== 测试1: 配置文件里设 storage.tsdb.block_duration ==="
mkdir -p /tmp/bdtest1
cat > /tmp/bdtest1/prometheus.yml <<'EOF'
global:
  scrape_interval: 5s
storage:
  tsdb:
    block_duration: 10m
scrape_configs: []
EOF

docker run --rm --name bdtest1 \
  -v /tmp/bdtest1/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v /tmp/bdtest1/data:/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus &
sleep 8
docker logs bdtest1 2>&1 | grep -iE 'block_duration|block-duration|error|unknown' | head -5
docker rm -f bdtest1 >/dev/null 2>&1 || true

echo
echo "=== 测试2: 观察默认启动日志里的 TSDB 参数 ==="
docker run --rm --name bdtest2 -d prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml 2>&1 | head -2
sleep 1
echo "(无配置文件会直接退出，改用下面的方式)"

set -e
APP_DIR=/mnt/d/projects/learning/prometheus/labs/lesson-01/app

# 1) 专用网络（服务名即 DNS 名，容器名与 --name 一致，配置里写服务名即可解析）
docker network create lesson01-net

# 2) 手写 /metrics 的示例应用（形态一：应用原生暴露）
docker run -d --name demo-app --network lesson01-net \
  -v "$APP_DIR":/app -w /app \
  python:3.12-slim python demo_app.py

# 3) node-exporter（形态二：独立 exporter 代理）
docker run -d --name node-exporter --network lesson01-net \
  prom/node-exporter:v1.10.2

# 4) Pushgateway（形态三：短生命周期任务的中转站）
docker run -d --name pushgateway --network lesson01-net -p 9091:9091 \
  prom/pushgateway:v1.11.1

# 5) Prometheus 本体（宿主 9095 -> 容器 9090，避开宿主机已占用的 9090）
docker run -d --name prometheus --network lesson01-net -p 9095:9090 \
  -v /mnt/d/projects/learning/prometheus/labs/lesson-01/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle

echo "=== 等待 10 秒让首轮抓取完成 ==="
sleep 10
docker ps --filter name=demo-app --filter name=node-exporter --filter name=pushgateway --filter name=prometheus \
  --format '{{.Names}}\t{{.Status}}'

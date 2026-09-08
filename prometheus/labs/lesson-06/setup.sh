#!/usr/bin/env bash
# 课6 环境搭建：Prometheus v3.14.0 + 可控基数/可控生死的 app
# 宿主端口：19094 (Prometheus)，避开课5占用的 19090/19093
set -e

LAB="labs/lesson-06"
NET="lesson06-net"
PROM="l6-prom"
APP="l6-app"
HOST_PORT=19094

echo "== 0. 清理上一轮残留 =="
docker rm -f $PROM $APP 2>/dev/null || true
docker network rm $NET 2>/dev/null || true

echo "== 1. 建网络 =="
docker network create $NET >/dev/null

echo "== 2. 构建 app 镜像 =="
docker build -t l6-app:latest $LAB/app

echo "== 3. 启动 app =="
docker run -d --name $APP --network $NET l6-app:latest

echo "== 4. 启动 Prometheus =="
docker run -d --name $PROM --network $NET \
  -p ${HOST_PORT}:9090 \
  -v "$(pwd)/$LAB/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle \
  --query.max-concurrency=20

echo "== 5. 等待就绪 =="
for i in $(seq 1 40); do
  if docker exec $PROM wget -qO- http://localhost:9090/-/ready 2>/dev/null | grep -q "Server is Ready"; then
    echo "Prometheus ready after ${i}s"
    break
  fi
  sleep 1
done

echo "== 6. 检查版本与目标 =="
# 注：v3.14.0 的 /api/v1/status/build_info 已移除（实测 404），改用启动日志取版本
docker logs $PROM 2>&1 | grep -m1 'Starting Prometheus Server' | sed 's/.*msg=//'

sleep 6
docker exec $PROM wget -qO- 'http://localhost:9090/api/v1/targets?state=active' \
  | python3 -c "
import sys,json
ts=json.load(sys.stdin)['data']['activeTargets']
for t in ts: print('target:', t['labels'].get('job'), t['scrapeUrl'], t.get('health'))
"
